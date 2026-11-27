import 'dart:io';

import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _sessionId = UuidValue('00000000-0000-4000-8000-000000000001');

class _Binding extends Fake implements RustdeskImpl {
  final sent = <String>[];
  final sentIds = <int>[];
  final created = <String>[];
  int nextId = 0;

  @override
  String mainGetCommonSync({required String key, dynamic hint}) =>
      '${++nextId}';

  @override
  int versionToNumber({required String v, dynamic hint}) =>
      v == '1.3.3' ? 1 : 2;

  @override
  Future<void> sessionSendFiles({
    required UuidValue sessionId,
    required int actId,
    required String path,
    required String to,
    required int fileNum,
    required bool includeHidden,
    required bool isRemote,
    required bool isDir,
    dynamic hint,
  }) async {
    expect(isRemote, isTrue);
    sent.add(to);
    sentIds.add(actId);
  }

  @override
  Future<void> sessionCreateDir({
    required UuidValue sessionId,
    required int actId,
    required String path,
    required bool isRemote,
    dynamic hint,
  }) async {
    expect(isRemote, isFalse);
    created.add(path);
  }

  @override
  Future<void> sessionCancelJob({
    required UuidValue sessionId,
    required int actId,
    dynamic hint,
  }) async {}
}

class _Session extends Fake implements FFI {
  @override
  final String id = 'download-test';
  @override
  UuidValue get sessionId => _sessionId;
  @override
  late final ffiModel = FfiModel(WeakReference(this));
}

class _Fetcher extends FileFetcher {
  _Fetcher() : super(() => _sessionId);
  List<String> emptyDirectories = [];

  @override
  Future<List<FileDirectory>> readEmptyDirs(
          String path, bool isLocal, bool showHidden) async =>
      emptyDirectories.map((path) => FileDirectory()..path = path).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Binding binding;
  late _Session session;
  late _Fetcher fetcher;
  late FileController controller;
  late DirectoryData destination;

  setUp(() {
    binding = _Binding();
    platformFFI.setBindingForTesting(binding);
    session = _Session();
    session.ffiModel.pi.version = '1.5.1';
    fetcher = _Fetcher();
    destination =
        DirectoryData(FileDirectory()..path = '/downloads', DirectoryOptions());
    controller = FileController(
      isLocal: false,
      getSessionID: () => _sessionId,
      rootState: WeakReference(session),
      jobController: JobController(() => _sessionId, () => null),
      fileFetcher: fetcher,
      getOtherSideDirectoryData: () => destination,
    );
    controller.directory.value.path = '/remote';
  });

  tearDown(() => session.ffiModel.dispose());

  Future<void> download(String name, {bool directory = false}) async {
    final entry = Entry()
      ..name = name
      ..path = '/remote/$name'
      ..entryType = directory ? 0 : 4;
    final items = SelectedItems(isLocal: false)..add(entry);
    await controller.sendFiles(items, destination);
  }

  test('downloads refuse peer listing names that escape the local folder',
      () async {
    await download('report.txt');
    expect(binding.sent, ['/downloads/report.txt']);
    binding.sent.clear();
    for (final windows in [false, true]) {
      destination.options.isWindows = windows;
      destination.directory.path = windows ? r'C:\downloads' : '/downloads';
      for (final name in [
        '../outside.txt',
        '/outside.txt',
        '.',
        '..',
        '',
        'bad\x00name',
        if (windows) ...[r'..\outside.txt', r'C:\outside.txt', r'\\host\share'],
      ]) {
        await download(name);
        expect(binding.sent, isEmpty, reason: name);
        expect(controller.jobController.jobTable.last.state, JobState.error);
      }
    }
    expect(controller.jobController.jobTable.last.canRetryTransfer, isFalse);
    await controller.jobController.jobDone({
      'id': '${controller.jobController.jobTable.last.id}',
      'file_num': '0',
    });
    expect(controller.jobController.jobTable.last.state, JobState.error);
  });

  test('retry starts a fresh download in its original directory', () async {
    final isWindows = Platform.isWindows;
    final originalDir = isWindows ? r'C:\downloads' : '/downloads';
    destination.directory.path = originalDir;
    destination.options.isWindows = isWindows;
    await download('report.txt');
    final failed = controller.jobController.jobTable.single;
    controller.jobController.jobError({
      'id': failed.id,
      'err': 'Write failed',
      'file_num': '0',
    });
    destination.directory.path = isWindows ? r'C:\other' : '/other';

    expect(failed.canRetryTransfer, isTrue);
    expect(await controller.retryTransfer(failed), isTrue);
    final retry = controller.jobController.jobTable.single;
    expect(binding.sentIds, [failed.id, retry.id]);
    expect(retry.id, isNot(failed.id));
    expect(binding.sent,
        List.filled(2, PathUtil.join(originalDir, 'report.txt', isWindows)));

    await controller.jobController.jobDone({
      'id': retry.id.toString(),
      'file_num': '0',
    });
    expect(retry.downloadDirectory, originalDir);
  });

  test('empty-directory downloads reject paths outside the selected folder',
      () async {
    for (final path in ['/remote/other/empty', '/remote/docs/../out']) {
      fetcher.emptyDirectories = ['/remote/docs/ok', path];
      await download('docs', directory: true);
      expect(binding.created, isEmpty, reason: path);
      expect(controller.jobController.jobTable.last.state, JobState.error);
    }
    fetcher.emptyDirectories = ['/remote/docs', '/remote/docs/sub/empty'];
    await download('docs', directory: true);
    expect(binding.created, ['/downloads/docs', '/downloads/docs/sub/empty']);
  });

  test('empty-directory downloads refuse existing local links', () async {
    final temporary =
        await Directory.systemTemp.createTemp('rustdesk_download_');
    addTearDown(() => temporary.delete(recursive: true));
    final outside = await Directory('${temporary.path}/outside').create();
    final downloads = await Directory('${temporary.path}/downloads').create();
    final link = Link(PathUtil.join(downloads.path, 'docs', Platform.isWindows));
    if (Platform.isWindows) {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'New-Item -ItemType Junction -Path $env:RUSTDESK_TEST_LINK '
              r'-Target $env:RUSTDESK_TEST_LINK_TARGET -ErrorAction Stop | Out-Null',
        ],
        environment: {
          'RUSTDESK_TEST_LINK': link.path,
          'RUSTDESK_TEST_LINK_TARGET': outside.path,
        },
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
    } else {
      await link.create(outside.path);
    }
    expect(
        await link.resolveSymbolicLinks(), await outside.resolveSymbolicLinks());
    destination.directory.path = downloads.path;
    destination.options.isWindows = Platform.isWindows;
    fetcher.emptyDirectories = ['/remote/docs/empty'];
    await download('docs', directory: true);
    expect(binding.created, isEmpty);
    expect(controller.jobController.jobTable.last.state, JobState.error);
  });
}

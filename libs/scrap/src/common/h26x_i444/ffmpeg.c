#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <libavcodec/avcodec.h>
#include <libavutil/dict.h>
#include <libavutil/hwcontext.h>

typedef struct {
    AVCodecContext *context;
    AVPacket *packet;
    AVFrame *frame;
} Codec;

typedef void (*PacketCallback)(void *, const uint8_t *, int, int64_t, int);
typedef int (*FrameCallback)(void *, const uint8_t *, int, const uint8_t *, int,
                             const uint8_t *, int, int, int);

void rd_i444_free(Codec *codec) {
    if (codec) {
        av_frame_free(&codec->frame);
        av_packet_free(&codec->packet);
        avcodec_free_context(&codec->context);
        free(codec);
    }
}

static Codec *allocate(const AVCodec *implementation) {
    if (!implementation)
        return NULL;
    Codec *codec = calloc(1, sizeof(*codec));
    if (codec) {
        codec->context = avcodec_alloc_context3(implementation);
        codec->packet = av_packet_alloc();
        codec->frame = av_frame_alloc();
        if (!codec->context || !codec->packet || !codec->frame) {
            rd_i444_free(codec);
            return NULL;
        }
    }
    return codec;
}

void rd_i444_bitrate(Codec *codec, int64_t bitrate) {
    codec->context->bit_rate = bitrate;
    codec->context->rc_max_rate = bitrate;
    codec->context->rc_buffer_size = (int)bitrate;
}

Codec *rd_i444_encoder(const char *name, int width, int height, int bitrate, int gop) {
    const AVCodec *implementation = avcodec_find_encoder_by_name(name);
    Codec *codec = allocate(implementation);
    if (!codec)
        return NULL;

    const int qsv = strcmp(name, "hevc_qsv") == 0;
    AVCodecContext *context = codec->context;
    context->width = width;
    context->height = height;
    context->pix_fmt = qsv ? AV_PIX_FMT_VUYX : AV_PIX_FMT_YUV444P;
    context->color_range = AVCOL_RANGE_MPEG;
    context->time_base.num = 1;
    context->time_base.den = 1000;
    context->framerate.num = 60;
    context->framerate.den = 1;
    context->gop_size = qsv && gop > 32767 ? 32767 : gop;
    context->max_b_frames = 0;
    rd_i444_bitrate(codec, bitrate);

    int result = 0;
    if (qsv) {
        AVDictionary *device_options = NULL;
        result = av_dict_set(&device_options, "child_device_type", "d3d11va", 0);
        if (result >= 0)
            result = av_hwdevice_ctx_create(&context->hw_device_ctx, AV_HWDEVICE_TYPE_QSV,
                                            "hw", device_options, 0);
        av_dict_free(&device_options);
    }
    static const char *const nvenc_options[][2] = {
        {"preset", "p1"}, {"tune", "ull"}, {"rc", "cbr"}, {"zerolatency", "1"},
        {"delay", "0"}, {NULL, NULL}
    };
    static const char *const qsv_options[][2] = {
        {"profile", "rext"}, {"async_depth", "1"}, {"preset", "veryfast"},
        {"look_ahead_depth", "0"}, {NULL, NULL}
    };
    const char *const (*settings)[2] = qsv ? qsv_options : nvenc_options;
    AVDictionary *options = NULL;
    for (int i = 0; result >= 0 && settings[i][0]; ++i)
        result = av_dict_set(&options, settings[i][0], settings[i][1], 0);
    if (result >= 0)
        result = avcodec_open2(context, implementation, &options);
    av_dict_free(&options);
    codec->frame->format = context->pix_fmt;
    codec->frame->width = width;
    codec->frame->height = height;
    if (result < 0 || av_frame_get_buffer(codec->frame, 0) < 0) {
        rd_i444_free(codec);
        return NULL;
    }
    return codec;
}

int rd_i444_encode(Codec *codec, const uint8_t *pixels, int stride, int64_t pts,
                   void *output, PacketCallback callback) {
    AVFrame *frame = codec->frame;
    int result = av_frame_make_writable(frame);
    if (result < 0)
        return result;
    if (frame->format == AV_PIX_FMT_VUYX) {
        const size_t plane_size = (size_t)stride * frame->height;
        for (int row = 0; row < frame->height; ++row) {
            uint8_t *packed = frame->data[0] + (size_t)row * frame->linesize[0];
            const uint8_t *y = pixels + (size_t)row * stride;
            const uint8_t *u = y + plane_size;
            const uint8_t *v = u + plane_size;
            for (int x = 0; x < frame->width; ++x) {
                packed[4 * (size_t)x] = v[x];
                packed[4 * (size_t)x + 1] = u[x];
                packed[4 * (size_t)x + 2] = y[x];
                packed[4 * (size_t)x + 3] = 255;
            }
        }
    } else {
        for (int plane = 0; plane < 3; ++plane) {
            for (int row = 0; row < frame->height; ++row) {
                memcpy(frame->data[plane] + (size_t)row * frame->linesize[plane],
                       pixels + ((size_t)plane * frame->height + row) * stride,
                       frame->width);
            }
        }
    }
    frame->pts = pts;
    result = avcodec_send_frame(codec->context, frame);
    if (result < 0)
        return result;
    while ((result = avcodec_receive_packet(codec->context, codec->packet)) >= 0) {
        AVPacket *packet = codec->packet;
        callback(output, packet->data, packet->size, packet->pts, (packet->flags & AV_PKT_FLAG_KEY) != 0);
        av_packet_unref(packet);
    }
    return result == AVERROR(EAGAIN) ? 0 : result;
}

Codec *rd_i444_decoder(int hevc, int threads) {
    const AVCodec *implementation = avcodec_find_decoder(hevc ? AV_CODEC_ID_HEVC : AV_CODEC_ID_H264);
    Codec *codec = allocate(implementation);
    if (!codec)
        return NULL;
    codec->context->thread_count = threads;
    codec->context->thread_type = FF_THREAD_SLICE;
    if (avcodec_open2(codec->context, implementation, NULL) < 0) {
        rd_i444_free(codec);
        return NULL;
    }
    return codec;
}

int rd_i444_decode(Codec *codec, const uint8_t *data, int size, void *output,
                   FrameCallback callback) {
    int result = av_new_packet(codec->packet, size);
    if (result < 0)
        return result;
    memcpy(codec->packet->data, data, size);
    result = avcodec_send_packet(codec->context, codec->packet);
    av_packet_unref(codec->packet);
    if (result < 0)
        return result;
    while ((result = avcodec_receive_frame(codec->context, codec->frame)) >= 0) {
        AVFrame *frame = codec->frame;
        if (frame->format != AV_PIX_FMT_YUV444P || frame->color_range == AVCOL_RANGE_JPEG)
            result = AVERROR_INVALIDDATA;
        else
            result = callback(output, frame->data[0], frame->linesize[0],
                              frame->data[1], frame->linesize[1],
                              frame->data[2], frame->linesize[2], frame->width, frame->height);
        av_frame_unref(frame);
        if (result < 0)
            return result;
    }
    return result == AVERROR(EAGAIN) ? 0 : result;
}

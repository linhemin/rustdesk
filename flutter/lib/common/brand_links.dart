import '../models/platform_model.dart';

/// Centralized product URLs so custom builds can override brand destinations
/// without scattering hardcoded links across desktop and mobile pages.
class BrandLinks {
  const BrandLinks._();

  static const String _defaultHomepage = 'https://rustdesk.com/';
  static const String _defaultPricing = 'https://rustdesk.com/pricing.html';
  static const String _defaultDownload = 'https://rustdesk.com/download';
  static const String _defaultPrivacy = 'https://rustdesk.com/privacy.html';

  static String _readOverride(String key, String fallback) {
    try {
      final v = bind.mainGetBuildinOption(key: key).trim();
      if (v.startsWith('http://') || v.startsWith('https://')) {
        return v;
      }
    } catch (_) {}
    return fallback;
  }

  static String get homepageUrl =>
      _readOverride('custom-homepage-url', _defaultHomepage);

  static String get pricingUrl =>
      _readOverride('custom-pricing-url', _defaultPricing);

  static String get downloadUrl =>
      _readOverride('custom-download-url', _defaultDownload);

  static String get privacyUrl =>
      _readOverride('custom-privacy-url', _defaultPrivacy);

  static String get displayDomain {
    final uri = Uri.tryParse(homepageUrl);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return 'rustdesk.com';
  }
}

import 'local_storage_service.dart';
import 'local_storage_constants.dart';

class LocalStorageDB {
  LocalStorageDB._();

  static Future<void> init() async {
    await LocalStorageService.init();
  }

  // User Credentials Management
  static String? get getUserId =>
      LocalStorageService.getString(LocalStorageConstants.userId);

  static String? get getFireBaseToken =>
      LocalStorageService.getString(LocalStorageConstants.firebaseToken);

  static Future<void> saveFireBaseToken(String token) async {
    await LocalStorageService.setString(LocalStorageConstants.firebaseToken, token);
  }

  static String? get getEmail =>
      LocalStorageService.getString(LocalStorageConstants.email);

  static String? get getToken =>
      LocalStorageService.getString(LocalStorageConstants.token);

  static Future<void> saveToken(String token) async {
    await LocalStorageService.setString(LocalStorageConstants.token, token);
  }

  static DateTime? get getTokenExpiry {
    final expiryString = LocalStorageService.getString(
      LocalStorageConstants.tokenExpiry,
    );
    if (expiryString != null) {
      try {
        return DateTime.parse(expiryString);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  static Future<void> saveTokenExpiry(DateTime expiry) async {
    await LocalStorageService.setString(
      LocalStorageConstants.tokenExpiry,
      expiry.toIso8601String(),
    );
  }

  static Future<void> saveUsername(String username) async {
    await LocalStorageService.setString(
      LocalStorageConstants.username,
      username,
    );
  }

  static Future<void> savePassword(String password) async {
    await LocalStorageService.setString(
      LocalStorageConstants.password,
      password,
    );
  }

  static Future<void> setRememberMe(bool rememberMe) async {
    await LocalStorageService.setBool(
      LocalStorageConstants.rememberMe,
      rememberMe,
    );
  }

  static String? get getUsername =>
      LocalStorageService.getString(LocalStorageConstants.username);

  static String? get getPassword =>
      LocalStorageService.getString(LocalStorageConstants.password);

  static bool get getRememberMe =>
      LocalStorageService.getBool(LocalStorageConstants.rememberMe) ?? false;

  static String? get getCartCount =>
      LocalStorageService.getString(LocalStorageConstants.cartCount);

  static Future<void> setCartCount(int? cartCount) async {
    await LocalStorageService.setInt(
      LocalStorageConstants.cartCount,
      cartCount ?? 0,
    );
  }

  // Profile Management
  static String? get getProfileImage =>
      LocalStorageService.getString(LocalStorageConstants.profileImage);

  static Future<void> saveProfileImage(String profileImage) async {
    await LocalStorageService.setString(
      LocalStorageConstants.profileImage,
      profileImage,
    );
  }

  static String? get getFirstName =>
      LocalStorageService.getString(LocalStorageConstants.firstName);

  static Future<void> saveFullName(String fullName) async {
    await LocalStorageService.setString(
      LocalStorageConstants.fullName,
      fullName,
    );
  }

   static Future<void> saveUserProfile(String userProfile) async {
    await LocalStorageService.setString(
      LocalStorageConstants.userProfile,
      userProfile,
    );
  }

  static Future<void> saveUserId(String user_id) async {
    await LocalStorageService.setString(LocalStorageConstants.userId, user_id);
  }

  static String? get getFullName =>
      LocalStorageService.getString(LocalStorageConstants.fullName);

      static String? get getUserProfile =>
      LocalStorageService.getString(LocalStorageConstants.userProfile);

  static String? get appSessionKey =>
      LocalStorageService.getString('sessionKey');

  // Energy Reading Form Data Methods
  static Future<void> saveEnergyReadingFormData(
    Map<String, dynamic> formData,
  ) async {
    await LocalStorageService.setJson(
      LocalStorageConstants.energyReadingFormData,
      formData,
    );
  }

  static Map<String, dynamic>? get getEnergyReadingFormData {
    try {
      return LocalStorageService.getJson(
        LocalStorageConstants.energyReadingFormData,
      );
    } catch (e) {

      clearCorruptedEnergyReadingData();
      return null;
    }
  }

  static Future<void> saveEnergyReadingIds({
    required String auditSchId,
    required String siteAuditSchId,
    required String siteId,
  }) async {
    await LocalStorageService.setString(
      LocalStorageConstants.energyReadingAuditSchId,
      auditSchId,
    );
    await LocalStorageService.setString(
      LocalStorageConstants.energyReadingSiteAuditSchId,
      siteAuditSchId,
    );
    await LocalStorageService.setString(
      LocalStorageConstants.energyReadingSiteId,
      siteId,
    );
  }

  static String? get getEnergyReadingAuditSchId =>
      LocalStorageService.getString(
        LocalStorageConstants.energyReadingAuditSchId,
      );

  static String? get getEnergyReadingSiteAuditSchId =>
      LocalStorageService.getString(
        LocalStorageConstants.energyReadingSiteAuditSchId,
      );

  static String? get getEnergyReadingSiteId =>
      LocalStorageService.getString(LocalStorageConstants.energyReadingSiteId);

  static Future<void> clearEnergyReadingData() async {
    await LocalStorageService.remove(
      LocalStorageConstants.energyReadingFormData,
    );
    await LocalStorageService.remove(
      LocalStorageConstants.energyReadingAuditSchId,
    );
    await LocalStorageService.remove(
      LocalStorageConstants.energyReadingSiteAuditSchId,
    );
    await LocalStorageService.remove(LocalStorageConstants.energyReadingSiteId);
  }

  static Future<void> clearCorruptedEnergyReadingData() async {
    await LocalStorageService.remove(
      LocalStorageConstants.energyReadingFormData,
    );
  }

  // Asset Audit Image Management Methods
  static Future<void> saveAssetAuditSelfie({
    required String siteAuditSchId,
    required String imageId,
    required String imageData,
  }) async {
    final key = '${LocalStorageConstants.assetAuditSelfieKey}$siteAuditSchId';
    await LocalStorageService.setJson(key, {
      'imageId': imageId,
      'imageData': imageData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

  }

  static Map<String, dynamic>? getAssetAuditSelfie(String siteAuditSchId) {
    final key = '${LocalStorageConstants.assetAuditSelfieKey}$siteAuditSchId';
    final data = LocalStorageService.getJson(key);
    if (data != null) {

      return data;
    }
    return null;
  }

  static Future<void> updateAssetAuditSelfie({
    required String siteAuditSchId,
    required String newImageId,
    required String newImageData,
  }) async {
    final key = '${LocalStorageConstants.assetAuditSelfieKey}$siteAuditSchId';
    await LocalStorageService.setJson(key, {
      'imageId': newImageId,
      'imageData': newImageData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

  }

  static Future<void> clearAssetAuditSelfie(String siteAuditSchId) async {
    final key = '${LocalStorageConstants.assetAuditSelfieKey}$siteAuditSchId';
    await LocalStorageService.remove(key);

  }

  // Asset Audit Form Data Persistence Methods
  static Future<void> saveAssetAuditFormData({
    required String siteAuditSchId,
    required String screenName,
    required Map<String, dynamic> formData,
  }) async {
    try {
      final key =
          '${LocalStorageConstants.assetAuditFormDataKey}${siteAuditSchId}_$screenName';
      await LocalStorageService.setJson(key, {
        'formData': formData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'screenName': screenName,
        'siteAuditSchId': siteAuditSchId,
      });

    } catch (e) {

    }
  }

  static Map<String, dynamic>? getAssetAuditFormData({
    required String siteAuditSchId,
    required String screenName,
  }) {
    try {
      final key =
          '${LocalStorageConstants.assetAuditFormDataKey}${siteAuditSchId}_$screenName';
      final data = LocalStorageService.getJson(key);
      if (data != null) {

        return data;
      }
      return null;
    } catch (e) {

      return null;
    }
  }

  static Future<void> updateAssetAuditFormData({
    required String siteAuditSchId,
    required String screenName,
    required Map<String, dynamic> newFormData,
  }) async {
    try {
      final key =
          '${LocalStorageConstants.assetAuditFormDataKey}${siteAuditSchId}_$screenName';
      await LocalStorageService.setJson(key, {
        'formData': newFormData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'screenName': screenName,
        'siteAuditSchId': siteAuditSchId,
      });

    } catch (e) {

    }
  }

  static Future<void> clearAssetAuditFormData({
    required String siteAuditSchId,
    required String screenName,
  }) async {
    final key =
        '${LocalStorageConstants.assetAuditFormDataKey}${siteAuditSchId}_$screenName';
    await LocalStorageService.remove(key);

  }

  static Future<void> clearAllAssetAuditFormData(String siteAuditSchId) async {
    final keys = LocalStorageService.getKeys();
    final prefix =
        '${LocalStorageConstants.assetAuditFormDataKey}$siteAuditSchId';
    for (final key in keys) {
      if (key.startsWith(prefix)) {
        await LocalStorageService.remove(key);
      }
    }

  }

  // Offline Ticket Management Methods
  static Future<void> saveOfflineTicket({
    required String siteAuditSchId,
    required Map<String, dynamic> completeTicketData,
  }) async {
    try {
      final key = '${LocalStorageConstants.offlineTicketKey}$siteAuditSchId';
      await LocalStorageService.setJson(key, {
        'completeTicketData': completeTicketData,
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
        'siteAuditSchId': siteAuditSchId,
      });

    } catch (e) {

    }
  }

  static Map<String, dynamic>? getOfflineTicket(String siteAuditSchId) {
    try {
      final key = '${LocalStorageConstants.offlineTicketKey}$siteAuditSchId';
      final data = LocalStorageService.getJson(key);
      if (data != null) {

        return data;
      }
      return null;
    } catch (e) {

      return null;
    }
  }

  static Future<void> updateOfflineTicket({
    required String siteAuditSchId,
    required Map<String, dynamic> updatedTicketData,
  }) async {
    try {
      final key = '${LocalStorageConstants.offlineTicketKey}$siteAuditSchId';
      await LocalStorageService.setJson(key, {
        'completeTicketData': updatedTicketData,
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
        'siteAuditSchId': siteAuditSchId,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

    } catch (e) {

    }
  }

  static Future<void> deleteOfflineTicket(String siteAuditSchId) async {
    try {
      final key = '${LocalStorageConstants.offlineTicketKey}$siteAuditSchId';
      await LocalStorageService.remove(key);

    } catch (e) {

    }
  }

  static List<Map<String, dynamic>> getAllOfflineTickets() {
    try {
      final keys = LocalStorageService.getKeys();
      final List<Map<String, dynamic>> tickets = [];
      for (final key in keys) {
        if (key.startsWith(LocalStorageConstants.offlineTicketKey)) {
          final data = LocalStorageService.getJson(key);
          if (data != null) {
            tickets.add(data);
          }
        }
      }

      return tickets;
    } catch (e) {

      return [];
    }
  }

  static bool isTicketDownloaded(String siteAuditSchId) {
    try {
      final key = '${LocalStorageConstants.offlineTicketKey}$siteAuditSchId';
      return LocalStorageService.containsKey(key);
    } catch (e) {

      return false;
    }
  }

  // Clear all data
  static Future<void> clearAllData() async {
    await LocalStorageService.clear();
  }

  // Logout functionality
  static Future<void> logout() async {

    // Clear all authentication-related data
    await LocalStorageService.remove(LocalStorageConstants.userId);
    await LocalStorageService.remove(LocalStorageConstants.token);
    await LocalStorageService.remove(LocalStorageConstants.tokenExpiry);
    await LocalStorageService.remove(LocalStorageConstants.firstName);
    await LocalStorageService.remove(LocalStorageConstants.fullName);
    await LocalStorageService.remove(LocalStorageConstants.email);
    
    // Clear profile image and user profile to prevent showing old login image
    await LocalStorageService.remove(LocalStorageConstants.profileImage);
    await LocalStorageService.remove(LocalStorageConstants.userProfile);

    // Clear saved credentials if remember me is not enabled
    if (!getRememberMe) {
      await LocalStorageService.remove(LocalStorageConstants.username);
      await LocalStorageService.remove(LocalStorageConstants.password);
      await LocalStorageService.remove(LocalStorageConstants.rememberMe);
    }

  }

  // Clear all saved credentials including remember me data
  static Future<void> clearAllCredentials() async {

    await LocalStorageService.remove(LocalStorageConstants.username);
    await LocalStorageService.remove(LocalStorageConstants.password);
    await LocalStorageService.remove(LocalStorageConstants.rememberMe);
    await LocalStorageService.remove(LocalStorageConstants.token);
    await LocalStorageService.remove(LocalStorageConstants.tokenExpiry);
    await LocalStorageService.remove(LocalStorageConstants.userId);
    await LocalStorageService.remove(LocalStorageConstants.firstName);
    await LocalStorageService.remove(LocalStorageConstants.email);

  }

  /// System setting `TICKET_ACCESS_RANGE` value in kilometers (e.g. `"1000"`).
  static String? get getTicketAccessRangeKm =>
      LocalStorageService.getString(LocalStorageConstants.ticketAccessRangeKm);

  static Future<void> saveTicketAccessRangeKm(String rangeKm) async {
    await LocalStorageService.setString(
      LocalStorageConstants.ticketAccessRangeKm,
      rangeKm.trim(),
    );
  }

  // Headers methods
  static Map<String, String> getHeadersWithToken() {
    return {"Authorization": 'Bearer ${LocalStorageDB.getToken}'};
  }

  static Map<String, String> getHeaders() {
    return {};
  }
}

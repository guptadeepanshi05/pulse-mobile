class LocalStorageConstants {
  LocalStorageConstants._();

  static const String hasRegulaDB = "hasRegulaDB";
  static const String languageScreen = "isLanguageScreenDone";
  static const String storyView = "isStoryView";

  static const String getConfiguration = "getConfiguration";
  static const String getContent = "getContent";

  // User credentials
  static const String userCreds = "userCreds";

  // Key names
  static const String userId = "userId";
  static const String email = "email";
  static const String token = "token";
  static const String tokenExpiry = "tokenExpiry";
  static const String cartCount = "cartCount";
  static const String profileImage = "profileImage";
  static const String firstName = "firstName";
  static const String fullName = "fullName";
  static const String firebaseToken = "firebaseToken";
  
  // Remember me functionality
  static const String username = "username";
  static const String password = "password";
  static const String rememberMe = "rememberMe";
  
  // Energy Reading Form Data
  static const String energyReadingFormData = "energyReadingFormData";
  static const String energyReadingAuditSchId = "energyReadingAuditSchId";
  static const String energyReadingSiteAuditSchId = "energyReadingSiteAuditSchId";
  static const String energyReadingSiteId = "energyReadingSiteId";
  
  // Asset Audit Image Management
  static const String assetAuditImages = "assetAuditImages";
  static const String assetAuditSelfieKey = "assetAuditSelfie_";
  
  // Asset Audit Form Data Persistence
  static const String assetAuditFormData = "assetAuditFormData";
  static const String assetAuditFormDataKey = "assetAuditFormData_";
  
  // Offline Ticket Management
  static const String offlineTickets = "offlineTickets";
  static const String offlineTicketKey = "offlineTicket_";

  // User Profile
  static const String userProfile = "userProfile";

  /// Ticket / site access radius from system-settings (`TICKET_ACCESS_RANGE`), in km.
  static const String ticketAccessRangeKm = "ticketAccessRangeKm";
}

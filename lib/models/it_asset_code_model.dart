class ItAssetCode {
  final int iamId;
  final String asset;
  final String assetType;
  final int tenantMstId;

  const ItAssetCode({
    required this.iamId,
    required this.asset,
    required this.assetType,
    required this.tenantMstId,
  });

  factory ItAssetCode.fromJson(Map<String, dynamic> json) {
    return ItAssetCode(
      iamId: int.tryParse(json['iam_id']?.toString() ?? '') ?? 0,
      asset: json['asset']?.toString() ?? '',
      assetType: json['asset_type']?.toString() ?? '',
      tenantMstId: int.tryParse(json['tenant_mst_id']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'iam_id': iamId,
      'asset': asset,
      'asset_type': assetType,
      'tenant_mst_id': tenantMstId,
    };
  }
}

/// Parsed response from GET /it-asset/it-asset/dropdown/{iatmId}.
class ItAssetCodeDropdown {
  final Map<String, List<ItAssetCode>> assetsByType;

  const ItAssetCodeDropdown({required this.assetsByType});

  /// Flattened list across all groups, de-duplicated by [ItAssetCode.asset].
  ///
  /// The backend occasionally returns the same asset twice (same `iam_id` and
  /// label). The dropdown widget requires unique values, so we keep the first
  /// occurrence and drop subsequent ones.
  List<ItAssetCode> get allAssets {
    final seen = <String>{};
    final result = <ItAssetCode>[];
    for (final list in assetsByType.values) {
      for (final item in list) {
        final key = item.asset.trim();
        if (key.isEmpty) continue;
        if (seen.add(key)) {
          result.add(item);
        }
      }
    }
    return result;
  }

  factory ItAssetCodeDropdown.fromResponse(dynamic data) {
    final map = <String, List<ItAssetCode>>{};
    if (data is! Map) {
      return ItAssetCodeDropdown(assetsByType: map);
    }

    for (final entry in data.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is! List) continue;

      final codes = <ItAssetCode>[];
      for (final item in value) {
        if (item is Map<String, dynamic>) {
          codes.add(ItAssetCode.fromJson(item));
        } else if (item is Map) {
          codes.add(ItAssetCode.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      if (codes.isNotEmpty) {
        map[key] = codes;
      }
    }

    return ItAssetCodeDropdown(assetsByType: map);
  }
}

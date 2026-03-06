class AriamiFeatureFlags {
  const AriamiFeatureFlags({
    this.enableV2Api = false,
    this.enableCatalogWrite = false,
    this.enableCatalogRead = false,
    this.enableArtworkPrecompute = false,
    this.enableDownloadJobs = false,
    this.enableApiScopedAuthForCliWeb = false,
  });

  final bool enableV2Api;
  final bool enableCatalogWrite;
  final bool enableCatalogRead;
  final bool enableArtworkPrecompute;
  final bool enableDownloadJobs;
  final bool enableApiScopedAuthForCliWeb;

  Map<String, dynamic> toJson() {
    return {
      'enableV2Api': enableV2Api,
      'enableCatalogWrite': enableCatalogWrite,
      'enableCatalogRead': enableCatalogRead,
      'enableArtworkPrecompute': enableArtworkPrecompute,
      'enableDownloadJobs': enableDownloadJobs,
      'enableApiScopedAuthForCliWeb': enableApiScopedAuthForCliWeb,
    };
  }
}

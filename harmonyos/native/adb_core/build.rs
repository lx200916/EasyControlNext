fn main() {
  napi_build_ohos::setup();

  let target = std::env::var("TARGET").unwrap_or_default();
  if !target.contains("ohos") {
    return;
  }

  let ndk = std::env::var("OHOS_NDK_HOME").unwrap_or_else(|_| {
    "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony".into()
  });

  // Prefer arch-specific sysroot lib dir matching the cargo target.
  let arch_lib = if target.starts_with("aarch64") {
    "aarch64-linux-ohos"
  } else if target.starts_with("arm") {
    "arm-linux-ohos"
  } else if target.starts_with("x86_64") {
    "x86_64-linux-ohos"
  } else {
    "aarch64-linux-ohos"
  };

  let lib_dir = format!("{ndk}/native/sysroot/usr/lib/{arch_lib}");
  println!("cargo:rustc-link-search=native={lib_dir}");
  println!("cargo:rustc-link-lib=dylib=native_media_vdec");
  println!("cargo:rustc-link-lib=dylib=native_media_acodec");
  println!("cargo:rustc-link-lib=dylib=native_media_codecbase");
  println!("cargo:rustc-link-lib=dylib=native_media_core");
  println!("cargo:rustc-link-lib=dylib=native_window");
  println!("cargo:rustc-link-lib=dylib=ohaudio");
  println!("cargo:rerun-if-env-changed=OHOS_NDK_HOME");
}

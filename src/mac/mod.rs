use swift_rs::swift;
pub use swift_rs::{Bool, Int, SRData, SRObjectArray, SRString};

swift!(pub fn encoder_init(
    width: Int,
    height: Int,
    out_file: SRString
) -> *mut std::ffi::c_void);

swift!(pub fn encoder_ingest_yuv_frame(
    enc: *mut std::ffi::c_void,
    width: Int,
    height: Int,
    display_time: Int,
    luminance_stride: Int,
    luminance_bytes: SRData,
    chrominance_stride: Int,
    chrominance_bytes: SRData
));

swift!(pub fn encoder_ingest_bgra_frame(
    enc: *mut std::ffi::c_void,
    width: Int,
    height: Int,
    display_time: Int,
    bytes_per_row: Int,
    bgra_bytes_raw: SRData
));

swift!(pub fn encoder_finish(enc: *mut std::ffi::c_void));

swift!(pub fn get_windows_info(
    filter: Bool,
    capture: Bool
) -> SRObjectArray<SRWindowInfo>);

swift!(pub fn get_app_icon(bundle_id: SRString) -> SRString);

#[repr(C)]
pub struct SRWindowInfo {
    pub title: SRString,
    pub app_name: SRString,
    pub bundle_id: SRString,
    pub is_on_screen: Bool,
    pub id: Int,
}

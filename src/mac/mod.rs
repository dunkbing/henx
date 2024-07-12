use swift_rs::swift;
pub use swift_rs::{Int, SRData, SRString, Bool, SRObjectArray};

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

swift!(pub fn get_windows_and_thumbnails(
    filter: Bool,
    capture: Bool
) -> SRObjectArray<SRWindowInfo>);

#[repr(C)]
pub struct IntTuple {
    pub item1: Int,
    pub item2: Int
}

swift!(pub fn get_tuples() -> SRObjectArray<IntTuple>);

#[repr(C)]
pub struct SRWindowInfo {
    pub title: SRString,
    pub app_name: SRString,
    pub bundle_id: SRString,
    pub is_on_screen: Bool,
    pub id: Int,
    pub thumbnail_data: SRData,
}

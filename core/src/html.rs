//! HTML related utilities

mod dimensions;
mod iterators;
mod layout;
mod line_wrapping;
pub(crate) mod rich_text; // Timffle
mod text_format;

pub use dimensions::Position;
pub use layout::context::LayoutContext;
pub use layout::{
    Layout, LayoutBox, LayoutContent, LayoutLine, LayoutMetrics, LayoutParams,
    lower_from_text_spans,
};
pub use line_wrapping::wrap_line;
pub use rich_text::{RichTextError, RichTextRun, parse_flash_rich_text}; // Timffle
pub use style_sheet::{CssStream, StyleSheet, parse_font_list, transform_dashes_to_camel_case};
pub use text_format::{FormatSpans, TextDisplay, TextFormat, TextSpan};

mod style_sheet;
#[cfg(test)]
mod test;

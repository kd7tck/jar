// jar_rustinclude - A modular, single-file Rust library for processing file includes.
// Inspired by stb_include.h and incstr.
//
// This library is designed to be "popped into" a project as a single file.
// It is `no_std` compatible, relying only on the `alloc` crate for dynamic types.
//
// To use, copy this file into your project (e.g., as `src/jar_rustinclude.rs`)
// and bring it into scope with `mod jar_rustinclude;`.
//
// Then you can create a `Processor` and use it to preprocess your files.
//
// # Example (`std` feature)
//
// ```no_run
// // In your project's `main.rs` or `lib.rs`, include this file as a module:
// mod jar_rustinclude;
//
// fn run() {
//     let source = jar_rustinclude::Processor::new()
//         .add_path("shaders")
//         .add_path("shaders/common")
//         .inject("#version 450 core\n#define APP\n")
//         .preprocess_file("shaders/main.glsl")
//         .unwrap();
//
//     println!("{}", source);
// }
// ```
//
// Public domain / MIT / Apache-2.0 -- your choice.
// Author: 2025, community contribution.

#![cfg_attr(not(feature = "std"), no_std)]
#![allow(dead_code)]

extern crate alloc;

use alloc::format;
use alloc::string::{String, ToString};
use alloc::vec::Vec;
use core::cell::RefCell;
use core::fmt::{self, Write};

/// Result type used throughout the library.
pub type Result<T> = core::result::Result<T, Error>;

/// Represents an error during preprocessing.
#[derive(Debug, Clone)]
pub struct Error {
    pub message: String,
    pub file: String,
    pub line: usize,
}

impl Error {
    fn new(msg: &str, file: &str, line: usize) -> Self {
        Self {
            message: msg.to_string(),
            file: file.to_string(),
            line,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}: error: {}", self.file, self.line, self.message)
    }
}

/// A preprocessor for resolving `#include` directives in text files.
///
/// This struct provides a simple builder-style interface for configuring the preprocessing options.
#[derive(Clone, Default)]
pub struct Processor<'a> {
    search_paths: Vec<&'a str>,
    inject: Option<&'a str>,
}

impl<'a> Processor<'a> {
    /// Creates a new, empty `Processor`.
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a single search path.
    pub fn add_path(mut self, path: &'a str) -> Self {
        self.search_paths.push(path);
        self
    }

    /// Adds multiple search paths from a semicolon-separated string.
    pub fn add_paths(mut self, paths: &'a str) -> Self {
        self.search_paths
            .extend(paths.split(';').map(|s| s.trim()).filter(|s| !s.is_empty()));
        self
    }

    /// Sets the code to be injected at the beginning of the output.
    pub fn inject(mut self, inject: &'a str) -> Self {
        self.inject = Some(inject);
        self
    }
}

#[cfg(feature = "std")]
impl<'a> Processor<'a> {
    /// Preprocesses a file from the filesystem.
    ///
    /// This is a convenience method that uses `std::fs::read_to_string` for file loading.
    /// It is only available when the `std` feature is enabled.
    pub fn preprocess_file(&self, path: &str) -> Result<String> {
        let content = std::fs::read_to_string(path)
            .map_err(|e| Error::new(&e.to_string(), path, 0))?;
        let file_loader = |p: &str| std::fs::read_to_string(p).ok();
        self.preprocess(&content, path, file_loader)
    }
}

impl<'a> Processor<'a> {
    /// Preprocesses an input string, resolving `#include` directives.
    ///
    /// This is the main entry point of the library. It takes an input string, a "virtual"
    /// filename for error reporting, and a file loader closure. The file loader is responsible
    /// for taking a path and returning the content of the file as an `Option<String>`.
    ///
    /// # Example (`no_std` context)
    ///
    /// ```no_run
    /// # mod jar_rustinclude {
    /// #     #![cfg_attr(not(feature = "std"), no_std)]
    /// #     #![allow(dead_code)]
    /// #     extern crate alloc;
    /// #     use alloc::format;
    /// #     use alloc::string::{String, ToString};
    /// #     use alloc::vec::Vec;
    /// #     use core::cell::RefCell;
    /// #     use core::fmt::{self, Write};
    /// #     pub type Result<T> = core::result::Result<T, Error>;
    /// #     #[derive(Debug, Clone)]
    /// #     pub struct Error {
    /// #         pub message: String,
    /// #         pub file: String,
    /// #         pub line: usize,
    /// #     }
    /// #     impl Error {
    /// #         fn new(msg: &str, file: &str, line: usize) -> Self {
    /// #             Self {
    /// #                 message: msg.to_string(),
    /// #                 file: file.to_string(),
    /// #                 line,
    /// #             }
    /// #         }
    /// #     }
    /// #     impl fmt::Display for Error {
    /// #         fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    /// #             write!(f, "{}:{}: error: {}", self.file, self.line, self.message)
    /// #         }
    /// #     }
    /// #     #[derive(Clone, Default)]
    /// #     pub struct Processor<'a> {
    /// #         search_paths: Vec<&'a str>,
    /// #         inject: Option<&'a str>,
    /// #     }
    /// #     impl<'a> Processor<'a> {
    /// #         pub fn new() -> Self {
    /// #             Self::default()
    /// #         }
    /// #         pub fn add_path(mut self, path: &'a str) -> Self {
    /// #             self.search_paths.push(path);
    /// #             self
    /// #         }
    /// #         pub fn add_paths(mut self, paths: &'a str) -> Self {
    /// #             self.search_paths.extend(paths.split(';').map(|s| s.trim()).filter(|s| !s.is_empty()));
    /// #             self
    /// #         }
    /// #         pub fn inject(mut self, inject: &'a str) -> Self {
    /// #             self.inject = Some(inject);
    /// #             self
    /// #         }
    /// #     }
    /// #     impl<'a> Processor<'a> {
    /// #         pub fn preprocess<F>(
    /// #             &self,
    /// #             input: &str,
    /// #             virtual_filename: &str,
    /// #             mut load_file: F,
    /// #         ) -> Result<String>
    /// #         where
    /// #             F: FnMut(&str) -> Option<String>,
    /// #         {
    /// #             // Implementation...
    /// #             Ok(String::new())
    /// #         }
    /// #     }
    /// # }
    /// use jar_rustinclude::Processor;
    /// use std::collections::HashMap;
    ///
    /// let mut file_system = HashMap::new();
    /// file_system.insert("common.glsl", "const float PI = 3.14159;");
    ///
    /// let file_loader = |path: &str| file_system.get(path).map(|s| s.to_string());
    ///
    /// let source = r#"
    ///     #include "common.glsl"
    ///     // ...
    /// "#;
    ///
    /// let processed_source = Processor::new()
    ///     .preprocess(source, "main.glsl", file_loader)
    ///     .unwrap();
    /// ```
    pub fn preprocess<F>(
        &self,
        input: &str,
        virtual_filename: &str,
        mut load_file: F,
    ) -> Result<String>
    where
        F: FnMut(&str) -> Option<String>,
    {
        INCLUDE_GUARD.with(|guard| guard.borrow_mut().clear());

        let mut output = String::new();
        if let Some(inject) = self.inject {
            writeln!(&mut output, "{}", inject)
                .map_err(|_| Error::new("failed to write inject", "", 0))?;
        }

        // Add initial #line directive for the main file.
        writeln!(
            &mut output,
            "#line 1 \"{}\"",
            escape_for_line_directive(virtual_filename)
        )
        .map_err(|_| Error::new("failed to write line directive", virtual_filename, 1))?;

        process_lines(
            input,
            virtual_filename,
            1,
            &mut output,
            self,
            &mut load_file,
        )?;

        Ok(output)
    }
}

thread_local! {
    static INCLUDE_GUARD: RefCell<Vec<String>> = RefCell::new(Vec::new());
}


/// Core recursive processor for file content.
fn process_lines<F>(
    content: &str,
    current_file: &str,
    start_line: usize,
    output: &mut String,
    processor: &Processor,
    load_file: &mut F,
) -> Result<()>
where
    F: FnMut(&str) -> Option<String>,
{
    let mut line_number = start_line;
    for raw_line in content.lines() {
        let line = raw_line.trim();

        if let Some(include_path) = parse_include(line) {
            let (resolved_path, file_content) =
                find_and_load_include(include_path, current_file, processor, load_file)
                    .map_err(|mut e| {
                        e.line = line_number;
                        e
                    })?;

            // Cycle detection
            let already_included = INCLUDE_GUARD.with(|guard| guard.borrow().contains(&resolved_path));
            if already_included {
                return Err(Error::new(
                    "include cycle detected",
                    current_file,
                    line_number,
                ));
            }

            INCLUDE_GUARD.with(|guard| guard.borrow_mut().push(resolved_path.clone()));

            // Emit #line directive for the new file.
            writeln!(
                output,
                "#line 1 \"{}\"",
                escape_for_line_directive(&resolved_path)
            )
            .map_err(|_| Error::new("failed to write line directive", &resolved_path, 1))?;

            process_lines(&file_content, &resolved_path, 1, output, processor, load_file)?;

            // Return to the original file context.
            writeln!(
                output,
                "#line {} \"{}\"",
                line_number + 1,
                escape_for_line_directive(current_file)
            )
            .map_err(|_| {
                Error::new(
                    "failed to write line directive",
                    current_file,
                    line_number + 1,
                )
            })?;

            INCLUDE_GUARD.with(|guard| {
                guard.borrow_mut().pop();
            });
        } else {
            writeln!(output, "{}", raw_line)
                .map_err(|_| Error::new("write to output failed", current_file, line_number))?;
        }

        line_number += 1;
    }
    Ok(())
}

/// Tries to find and load an included file from relative path or search paths.
fn find_and_load_include<'a, F>(
    include_path: &str,
    current_file: &str,
    processor: &Processor,
    load_file: &mut F,
) -> Result<(String, String)>
where
    F: FnMut(&str) -> Option<String>,
{
    // 1. Try relative to the current file's directory.
    if let Some(parent) = get_parent_path(current_file) {
        let candidate = join_paths(parent, include_path);
        if let Some(content) = load_file(&candidate) {
            return Ok((candidate, content));
        }
    }

    // 2. Try each search path.
    for &dir in &processor.search_paths {
        let candidate = join_paths(dir, include_path);
        if let Some(content) = load_file(&candidate) {
            return Ok((candidate, content));
        }
    }

    Err(Error::new(
        &format!("include file not found: '{}'", include_path),
        current_file,
        0, // The line number will be filled in by the caller.
    ))
}

/// Parses a line to see if it is an `#include` directive.
/// Returns the path if it is, otherwise `None`.
fn parse_include(line: &str) -> Option<&str> {
    let line = line.trim_start();
    if !line.starts_with("#include") {
        return None;
    }

    let rest = line[8..].trim_start();

    if rest.starts_with('"') {
        rest[1..].find('"').map(|end| &rest[1..1 + end])
    } else if rest.starts_with('<') {
        rest[1..].find('>').map(|end| &rest[1..1 + end])
    } else {
        None
    }
}

/// Escapes a string for use in a C-style #line directive.
fn escape_for_line_directive(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

/// Gets the parent directory of a path.
/// This is a simple `no_std` alternative to `std::path::Path::parent`.
fn get_parent_path(path: &str) -> Option<&str> {
    path.rfind(|c| c == '/' || c == '\\').map(|i| &path[..i])
}

/// Joins two path segments.
/// This is a simple `no_std` alternative to `std::path::Path::join`.
fn join_paths(base: &str, child: &str) -> String {
    if base.is_empty() {
        return child.to_string();
    }
    let mut b = String::with_capacity(base.len() + 1 + child.len());
    b.push_str(base);
    if !base.ends_with('/') && !base.ends_with('\\') {
        b.push('/');
    }
    b.push_str(child);
    b
}

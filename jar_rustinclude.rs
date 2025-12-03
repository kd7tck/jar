// jar_rustinclude - A modular, single-file Rust library for processing file includes.
// Inspired by stb_include.h and incstr.
//
// This library is designed to be "popped into" a project as a single file.
// It is `no_std` compatible, relying only on the `alloc` crate for dynamic types.
//
// To use, copy this file into your project (e.g., as `src/jar_rustinclude.rs`)
// and bring it into scope with `mod jar_rustinclude;`. Then you can call
// `jar_rustinclude::preprocess`.
//
// Public domain / MIT / Apache-2.0 -- your choice.
// Author: 2025, community contribution.

#![no_std]
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

/// Configuration for the preprocessing.
#[derive(Clone)]
pub struct Config<'a> {
    /// Semicolon-separated include search directories.
    pub search_paths: &'a str,
    /// Code to inject at the beginning of the output.
    pub inject: Option<&'a str>,
    /// The filename to use for the initial input string, for error reporting and relative includes.
    pub virtual_filename: &'a str,
}

thread_local! {
    static INCLUDE_GUARD: RefCell<Vec<String>> = RefCell::new(Vec::new());
}

/// Preprocesses an input string, resolving `#include` directives.
///
/// This is the main entry point of the library. It takes an input string, a configuration,
/// and a file loader closure. The file loader is responsible for taking a path and
/// returning the content of the file as an `Option<String>`.
///
/// # Example
/// ```no_run
/// // In your project's `main.rs` or `lib.rs`, include this file as a module:
/// mod jar_rustinclude;
///
/// fn run() {
///     // In a `std` environment, you can use `std::fs` to load files.
///     let file_loader = |path: &str| std::fs::read_to_string(path).ok();
///
///     let config = jar_rustinclude::Config {
///         search_paths: "shaders;shaders/common",
///         inject: Some("#version 450 core\n#define APP\n"),
///         virtual_filename: "main.glsl",
///     };
///
///     let source = r#"
///     #include "common.glsl"
///
///     void main() {
///         gl_FragColor = vec4(1.0);
///     }
///     "#;
///
///     let processed_source = jar_rustinclude::preprocess(source, &config, file_loader).unwrap();
///     println!("{}", processed_source);
/// }
/// ```
pub fn preprocess<F>(input: &str, config: &Config<'_>, mut load_file: F) -> Result<String>
where
    F: FnMut(&str) -> Option<String>,
{
    INCLUDE_GUARD.with(|guard| guard.borrow_mut().clear());

    let mut output = String::new();
    if let Some(inject) = config.inject {
        writeln!(&mut output, "{}", inject)
            .map_err(|_| Error::new("failed to write inject", "", 0))?;
    }

    // Add initial #line directive for the main file.
    writeln!(
        &mut output,
        "#line 1 \"{}\"",
        escape_for_line_directive(config.virtual_filename)
    )
    .map_err(|_| Error::new("failed to write line directive", config.virtual_filename, 1))?;

    process_lines(
        input,
        config.virtual_filename,
        1,
        &mut output,
        config,
        &mut load_file,
    )?;

    Ok(output)
}

/// Core recursive processor for file content.
fn process_lines<F>(
    content: &str,
    current_file: &str,
    start_line: usize,
    output: &mut String,
    config: &Config<'_>,
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
                find_and_load_include(include_path, current_file, config, load_file)
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

            process_lines(&file_content, &resolved_path, 1, output, config, load_file)?;

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
    config: &Config<'a>,
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
    for dir in config.search_paths.split(';') {
        let dir = dir.trim();
        if dir.is_empty() {
            continue;
        }
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

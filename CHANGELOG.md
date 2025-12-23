# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Changed
- Updated Elixir to ~> 1.11
- Replaced Briefly test dependency with ExUnit's :tmp_dir

## [0.5.2] - 2021-09-16
### Added
- Added WIP visibility handling with callbacks and converters
- Runtime configuration for filesystems via the app env

## [0.5.1] - 2021-09-12
### Changed
- `Hako.RelativePath.join_prefix` does make sure trailing slashes are retained


## [0.5.0] - 2020-08-16
### Added
- New `Hako.Filesystem` callback `copy/4` to implement copy between filesystems
- New `Hako.Filesystem` callback `file_exists/2`
- New `Hako.Filesystem` callback `list_contents/2`
- New `Hako.Filesystem` callback `create_directory/2`
- New `Hako.Filesystem` callback `delete_directory/2`
- New `Hako.Filesystem` callback `clear/1`


## [0.4.0] - 2020-07-31
### Added
- New `Hako.Filesystem` callback `copy/4` to implement copy between filesystems


## [0.3.0] - 2020-07-29
### Added
- New `Hako.Filesystem` callback `read_stream/2`
- Added `:otp_app` key to `use Hako.Filesystem` macro to be able to store settings
in config files
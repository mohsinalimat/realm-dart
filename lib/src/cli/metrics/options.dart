////////////////////////////////////////////////////////////////////////////////
//
// Copyright 2021 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////////

import 'dart:io';

import 'package:build_cli_annotations/build_cli_annotations.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:path/path.dart' as path;
import 'target_os_type.dart';

part 'options.g.dart';

@CliOptions()
class Options {
  final TargetOsType? targetOsType;
  final String? targetOsVersion;
  final String? flutterRoot;
  final String pubspecPath;

  @CliOption(abbr: 'v', help: 'Show additional command output.')
  bool verbose = false;

  Options({this.targetOsType, this.targetOsVersion, this.flutterRoot, String? pubspecPath}) 
    : pubspecPath = path.join(path.current, pubspecPath ?? 'pubspec.yaml');
}

extension OptionsEx on Options {}

String get usage => _$parserForOptions.usage;

ArgParser populateOptionsParser(ArgParser p) => _$populateOptionsParser(p);

Options parseOptionsResult(ArgResults results) => _$parseOptionsResult(results);

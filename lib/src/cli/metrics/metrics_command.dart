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

import 'dart:async';

import 'package:args/command_runner.dart';

import 'flutter_info.dart';
import 'metrics.dart';
import 'options.dart';

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

import 'utils.dart';

class MetricsCommand extends Command<void> {
  @override
  final String description = 'Report anonymized builder metrics to Realm';

  @override
  final String name = 'metrics';

  MetricsCommand() {
    populateOptionsParser(argParser);
  }

  @override
  FutureOr<void>? run() async {
    await safe(() async {
      final options = parseOptionsResult(argResults!);
      await uploadMetrics(options);
    });
  }
}

Future<void> uploadMetrics(Options options) async {
  final pubspecPath = options.pubspecPath;
  final pubspec = Pubspec.parse(await File(pubspecPath).readAsString());

  hierarchicalLoggingEnabled = true;
  log.level = options.verbose ? Level.INFO : Level.WARNING;

  final skipUpload = isRealmCI || Platform.environment['CI'] != null || Platform.environment['REALM_DISABLE_ANALYTICS'] != null;
  if (skipUpload && !isRealmCI) {
    // skip early
    log.info('Skipping metrics upload');
    return;
  }

  final flutterInfo = await FlutterInfo.get(options);
  final hostId = await machineId();

  final metrics = await generateMetrics(
    distinctId: hostId,
    targetOsType: options.targetOsType,
    targetOsVersion: options.targetOsVersion,
    anonymizedMacAddress: hostId,
    anonymizedBundleId: pubspec.name.strongHash(),
    framework: flutterInfo != null ? 'Flutter' : 'Dart',
    frameworkVersion: flutterInfo != null
        ? [
            '${flutterInfo.frameworkVersion}',
            if (flutterInfo.channel != null) '(${flutterInfo.channel})', // to mimic Platform.version
            if (flutterInfo.frameworkCommitDate != null) '(${flutterInfo.frameworkCommitDate})', // -"-
          ].join(' ')
        : Platform.version,
  );

  const encoder = JsonEncoder.withIndent('  ');
  final payload = encoder.convert(metrics.toJson());
  log.info('Uploading metrics for ${pubspec.name}...\n$payload');
  final base64Payload = base64Encode(utf8.encode(payload));

  if (skipUpload) {
    // skip late
    log.info('Skipping metrics upload (late)');
    return;
  }

  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
        'https://webhooks.mongodb-realm.com'
        '/api/client/v2.0/app/realmsdkmetrics-zmhtm/service/metric_webhook/incoming_webhook/metric'
        '?data=$base64Payload}',
      ),
    );
    await request.close();
  } finally {
    client.close(force: true);
  }
}

Future<Digest> machineId() async {
  var id = await safe(() async {
    if (Platform.isLinux) {
      // For linux use /etc/machine-id
      // Can be changed by administrator but with unpredictable consequences!
      // (see https://man7.org/linux/man-pages/man5/machine-id.5.html)
      final process = await Process.start('cat', ['/etc/machine-id']);
      return await process.stdout.transform(utf8.decoder).join();
    } else if (Platform.isMacOS) {
      // For MacOS, use the IOPlatformUUID value from I/O Kit registry in
      // IOPlatformExpertDevice class
      final process = await Process.start('ioreg', [
        '-rd1',
        '-c',
        'IOPlatformExpertDevice',
      ]);
      final id = await process.stdout.transform(utf8.decoder).join();
      final r = RegExp('"IOPlatformUUID" = "([^"]*)"', dotAll: true);
      return r.firstMatch(id)?.group(1); // extract IOPlatformUUID
    } else if (Platform.isWindows) {
      // For Windows, use the key MachineGuid in registry:
      // HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography
      // Can be changed by administrator but with unpredictable consequences!
      //
      // It is generated during OS installation and won't change unless you make
      // another OS update or re-install. Depending on the OS version it may
      // contain the network adapter MAC address embedded (plus some other numbers,
      // including random), or a pseudorandom number.
      //
      // Consider using System.Identity.UniqueID instead.
      // (see https://docs.microsoft.com/en-gb/windows/win32/properties/props-system-identity-uniqueid)
      final process = await Process.start(
        '${Platform.environment['WINDIR']}\\System32\\Reg.exe',
        [
          'QUERY',
          r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ],
      );
      return await process.stdout.transform(systemEncoding.decoder).join();
    }
  }, message: 'failed to get machine id');
  id ??= Platform.localHostname; // fallback
  return id.strongHash(); // strong hash for privacy
}

extension _StringEx on String {
  static const _defaultSalt = <int>[75, 97, 115, 112, 101, 114, 32, 119, 97, 115, 32, 104, 101, 114];
  Digest strongHash({List<int> salt = _defaultSalt}) => sha256.convert([...salt, ...utf8.encode(this)]);
}

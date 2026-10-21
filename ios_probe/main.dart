// Isolated iOS FSRS-7 Rust static library / Dart FFI feasibility check.
// Atlas data is never read or written. The only file is a temporary CI marker
// INSIDE the isolated probe app sandbox.
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

const nonce = String.fromEnvironment('ATLAS_FSRS7_IOS_NONCE', defaultValue: 'NONE');

final class Memory extends Struct {
  @Float()
  external double stability;
  @Float()
  external double difficulty;
  @Float()
  external double stabilityFast;
}

final class Choice extends Struct {
  external Memory memory;
  @Float()
  external double intervalDays;
}

final class Next extends Struct {
  external Choice again;
  external Choice hard;
  external Choice good;
  external Choice easy;
}

typedef NativeVersion = Uint32 Function();
typedef DartVersion = int Function();
typedef NativeSize = IntPtr Function();
typedef DartSize = int Function();
typedef NativeNext = Int32 Function(Pointer<Memory>, Float, Float, Pointer<Next>);
typedef DartNext = int Function(Pointer<Memory>, double, double, Pointer<Next>);

void ensure(bool okay, String reason) {
  if (!okay) throw StateError(reason);
}

String probe() {
  ensure(Platform.isIOS, 'Expected iOS, not ${Platform.operatingSystem}');
  // Apple App Store-safe pattern: statically link Rust, resolve from process.
  final lib = DynamicLibrary.process();
  final version = lib.lookupFunction<NativeVersion, DartVersion>('atlas_fsrs7_engine_version');
  final abi = lib.lookupFunction<NativeVersion, DartVersion>('atlas_fsrs7_abi_version');
  final count = lib.lookupFunction<NativeVersion, DartVersion>('atlas_fsrs7_parameter_count');
  final stateSize = lib.lookupFunction<NativeSize, DartSize>('atlas_fsrs7_state_size');
  final resultSize = lib.lookupFunction<NativeSize, DartSize>('atlas_fsrs7_output_size');
  final next = lib.lookupFunction<NativeNext, DartNext>('atlas_fsrs7_next');
  ensure(version() == 7, 'Unexpected Rust model version: ${version()}');
  ensure(abi() == 1, 'Unexpected C FFI ABI: ${abi()}');
  ensure(count() == 34, 'FSRS-7 must have 34 weights');
  ensure(stateSize() == 12 && stateSize() == sizeOf<Memory>(), 'Memory ABI size mismatch');
  ensure(resultSize() == 64 && resultSize() == sizeOf<Next>(), 'Next ABI size mismatch');

  final output = calloc<Next>();
  final previous = calloc<Memory>();
  try {
    ensure(next(nullptr, 0, 0.9, output) == 0, 'First review native call failed');
    ensure((output.ref.good.memory.stability - 3.9221).abs() < 0.025,
        'Initial stability differs from pinned upstream golden');
    ensure((output.ref.good.memory.stabilityFast - 3.13768).abs() < 0.025,
        'Initial fast stability differs from pinned upstream golden');
    ensure((output.ref.good.intervalDays - 4.7777247).abs() < 0.1,
        'First Good interval differs from pinned upstream golden');
    previous.ref.stability = output.ref.good.memory.stability;
    previous.ref.difficulty = output.ref.good.memory.difficulty;
    previous.ref.stabilityFast = output.ref.good.memory.stabilityFast;
    ensure(next(previous, 10 / 1440, 0.9, output) == 0,
        'Same-day ten-minute FSRS-7 transition failed');
    final days = output.ref.good.intervalDays;
    const windowsAndAndroid = 10.071414947509766;
    ensure((days - windowsAndAndroid).abs() < 0.02,
        'iOS FSRS-7 result differs from Windows/Android reference: $days');
    ensure(next(nullptr, double.nan, 0.9, output) == -2,
        'Nonfinite elapsed time was not rejected');
    ensure(next(nullptr, 0, 0.99, output) == -2,
        'Retention 0.99 was not rejected by prototype bounds');
    return 'ENGINE=7 ABI=1 PARAMS=34 MEMORY=12 OUTPUT=64 '
        'TEN_MIN_GOOD_DAYS=$days PLATFORM=${Platform.operatingSystem}';
  } finally {
    calloc.free(previous);
    calloc.free(output);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  String status = 'FAIL';
  String info;
  try {
    info = probe();
    status = 'PASS';
  } catch (e, s) {
    info = '$e\n$s';
  }
  final marker = File('${Directory.systemTemp.path}/atlas-fsrs7-ios-result.txt');
  // Crash or sandbox write errors must surface in Simulator CI instead of false PASS.
  marker.writeAsStringSync('STATUS=$status\nNONCE=$nonce\nINFO=$info\n', flush: true);
  // ignore: avoid_print
  print('ATLAS_FSRS7_IOS_DART_FFI_SMOKE=$status;NONCE=$nonce;DETAIL=$info');
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('Atlas FSRS-7 — iOS Lab')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rust / Dart FFI: $status', style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 18),
          SelectableText(info),
          const SizedBox(height: 18),
          const Text('Isolated test only. No Atlas user data accessed.'),
        ]),
      ),
    ),
  ));
}

// Watch newly finalized blocks over the WebSocket feed (exits after 3 blocks, Ctrl-C, or EXAMPLE_SECONDS).
import 'dart:async';
import 'dart:io';

import 'package:janzeer_sdk/janzeer_sdk.dart';

Future<void> main() async {
  final env = Platform.environment;
  final ws = await JanzeerRpcWs.connect(
      env['JANZEER_WS_URL'] ?? 'ws://localhost:7019/rpc/ws',
      onEvent: (e) => print('[ws] $e'));

  final tip = await ws.getTip();
  final fromHeight = (tip.height - 2).clamp(1, tip.height);
  final completer = Completer<void>();
  var seen = 0;
  final wantBlocks = int.tryParse(env['EXAMPLE_BLOCKS'] ?? '') ?? 3;

  final sub = await ws.subscribeNewBlocks(
      NewBlocksParams(fromHeight: fromHeight, includeTransactions: false), (b) {
    print(
        'block ${b.height} ${b.hash} producer ${b.producer} txs ${b.transactionsCount}');
    seen++;
    if (seen >= wantBlocks && !completer.isCompleted) {
      completer.complete();
    }
  });

  final seconds = int.tryParse(env['EXAMPLE_SECONDS'] ?? '') ?? 40;
  print(
      'watching blocks from height $fromHeight (exits after $wantBlocks blocks or $seconds s)…');

  StreamSubscription<ProcessSignal>? sigintSub;
  if (!Platform.isWindows) {
    sigintSub = ProcessSignal.sigint.watch().listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
  }

  await Future.any([
    completer.future,
    Future<void>.delayed(Duration(seconds: seconds)),
  ]);

  await sigintSub?.cancel();
  await sub.unsubscribe();
  await ws.close();
}

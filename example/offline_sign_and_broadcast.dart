// Three-step flow: 1) query nonce online, 2) sign offline into file, 3) broadcast online.
import 'dart:convert';
import 'dart:io';

import 'package:janzeer_sdk/janzeer_sdk.dart';

Future<void> main() async {
  final env = Platform.environment;
  final client =
      JanzeerClient(env['JANZEER_NODE_URL'] ?? 'http://localhost:7019');
  final rpc = JanzeerRpc(env['JANZEER_RPC_URL'] ?? 'http://localhost:7019');
  final account = Account.fromMnemonic(env['JANZEER_E2E_MNEMONIC'] ??
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about');
  final to = env['JANZEER_E2E_RECIPIENT'] ??
      '0x598b1301acef3baba6ce25e38dd17b723f7b98b1';
  final offlineFile = File(env['JANZEER_OFFLINE_FILE'] ??
      '${Directory.systemTemp.path}/janzeer_offline_tx.json');

  try {
    // 1. Online, no key: read network id and the sender's next nonce.
    final info = await client.info();
    final nonce = await client.nonce(account.address);
    print(
        '1. online: network=${info.networkId} nonce=$nonce for ${account.checksumAddress}');

    // 2. Offline, with the key: sign the transfer locally and save JSON to file.
    // This step makes no network call. The nonce must still be the account's next
    // nonce when the transaction is broadcast, otherwise the node rejects it.
    final tx = account.signTx(TxBuilder.transfer(
        from: account.address,
        to: to,
        amount: '1.25',
        data: 'offline signed transfer',
        nonce: nonce,
        networkId: info.networkId));
    final offlineHash = tx.hash;
    await offlineFile.writeAsString(jsonEncode(tx.toJson()));
    print('2. offline: signed tx $offlineHash saved to ${offlineFile.path}');

    // 3. Online, no key: read file back, extract type, broadcast raw transaction and wait for finality.
    final json =
        jsonDecode(await offlineFile.readAsString()) as Map<String, dynamic>;
    final typeName = json.remove('type') as String;
    final type = TxType.values.firstWhere((t) => t.wireName == typeName);
    final body = json.cast<String, Object?>();

    final res = await rpc.sendRawTransaction(type, body);
    if (res.hash != offlineHash) {
      throw StateError(
          'Returned hash ${res.hash} does not match offline hash $offlineHash');
    }

    final fin = await waitForFinality(rpc, res.hash);
    print(
        '3. online: broadcast ${res.hash} FINAL in block ${fin.blockHeight} (receipt ok: ${fin.receipt?.successful})');
  } finally {
    if (await offlineFile.exists()) {
      await offlineFile.delete();
    }
    client.close();
    rpc.close();
  }
}

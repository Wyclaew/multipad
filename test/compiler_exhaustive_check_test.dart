import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/widgets/vault_item_card.dart';

void main() {
  testWidgets('VaultItemCard compiles and displays bankAccount item', (tester) async {
    final item = VaultItem(
      id: 'b1',
      title: 'Bank Checking',
      type: VaultItemType.bankAccount,
      bankName: 'Test Bank',
      bankIban: 'TR980006100512345678901234',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultItemCard(
            item: item,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Bank Checking'), findsOneWidget);
  });
}

import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

enum EmoneyCardBrand { mandiriEmoney, bcaFlazz, briBrizzi, bniTapCash, unknown }

class EmoneyTransaction {
  final int amountRupiah;
  final String? label;

  const EmoneyTransaction({required this.amountRupiah, this.label});

  Map<String, dynamic> toJson() => {
        'amountRupiah': amountRupiah,
        'label': label,
      };

  factory EmoneyTransaction.fromJson(Map<String, dynamic> json) =>
      EmoneyTransaction(
        amountRupiah: (json['amountRupiah'] as num).toInt(),
        label: json['label'] as String?,
      );
}

class EmoneyBalance {
  final EmoneyCardBrand brand;
  final String cardUid;
  final int balanceRupiah;
  final List<EmoneyTransaction> recentTransactions;

  const EmoneyBalance({
    required this.brand,
    required this.cardUid,
    required this.balanceRupiah,
    this.recentTransactions = const [],
  });

  Map<String, dynamic> toJson() => {
        'brand': brand.name,
        'cardUid': cardUid,
        'balanceRupiah': balanceRupiah,
        'recentTransactions':
            recentTransactions.map((transaction) => transaction.toJson()).toList(),
      };

  factory EmoneyBalance.fromJson(Map<String, dynamic> json) => EmoneyBalance(
        brand: EmoneyCardBrand.values.firstWhere(
          (candidate) => candidate.name == json['brand'],
          orElse: () => EmoneyCardBrand.unknown,
        ),
        cardUid: json['cardUid'] as String,
        balanceRupiah: (json['balanceRupiah'] as num).toInt(),
        recentTransactions: (json['recentTransactions'] as List<dynamic>? ??
                const <dynamic>[])
            .map(
              (entry) =>
                  EmoneyTransaction.fromJson(entry as Map<String, dynamic>),
            )
            .toList(),
      );
}

abstract class NfcServiceBase {
  Future<Either<Failure, bool>> isAvailable();
  Future<Either<Failure, bool>> isEnabled();
  Future<Either<Failure, String>> readCardUid();
  Future<Either<Failure, EmoneyBalance>> readEmoneyBalance({
    String? expectedCardUid,
  });
}

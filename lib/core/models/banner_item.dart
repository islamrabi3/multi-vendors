import 'package:equatable/equatable.dart';

class BannerItem extends Equatable {
  const BannerItem({required this.id, required this.imageUrl, this.vendorId});

  final String id;
  final String imageUrl;
  final String? vendorId;

  factory BannerItem.fromMap(Map<String, dynamic> map) => BannerItem(
        id: map['id'] as String,
        imageUrl: map['image_url'] as String,
        vendorId: map['vendor_id'] as String?,
      );

  @override
  List<Object?> get props => [id, imageUrl, vendorId];
}

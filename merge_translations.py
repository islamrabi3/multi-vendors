import json
import os

translations = {
  "missingSupabaseConfigurationnn1": "إعدادات Supabase مفقودة.\\n\\n",
  "multiVendor": "متعدد البائعين",
  "orderFood": "اطلب طعاماً",
  "sellAsAVendor": "بيع كتاجر",
  "deliverOrders": "توصيل الطلبات",
  "available": "متاح",
  "active": "نشط",
  "earnings": "الأرباح",
  "goOnlineToSeeAvailableOrders": "ابدأ الاتصال لرؤية الطلبات المتاحة",
  "noOrdersWaitingForPickup": "لا توجد طلبات في انتظار الاستلام",
  "orderClaimedHeadToTheStore": "تم قبول الطلب - توجه إلى المتجر!",
  "noDeliveriesYet": "لا توجد عمليات توصيل بعد",
  "pickedUp": "تم الاستلام",
  "noActiveDeliverynpullToRefresh": "لا توجد عملية توصيل نشطة.\\nاسحب للتحديث · ",
  "overview": "نظرة عامة",
  "vendors": "البائعين",
  "orders": "الطلبات",
  "promos": "العروض",
  "suspended": "معلق",
  "open": "مفتوح",
  "closed": "مغلق",
  "noVendorsHere": "لا يوجد بائعون هنا",
  "couldNotLoadThisOrder": "تعذر تحميل هذا الطلب.",
  "orderCancelled": "تم إلغاء الطلب",
  "noOrdersInThisView": "لا توجد طلبات في هذا العرض",
  "addATitleOrImageFirst": "يرجى إضافة عنوان أو صورة أولاً.",
  "bannerPublished": "تم نشر البانر",
  "enterACodeAndAValidDiscount": "أدخل كوداً وقيمة خصم صالحة.",
  "couponCreated": "تم إنشاء الكوبون",
  "pending": "قيد الانتظار",
  "suspended1": "معلق",
  "active1": "نشط",
  "couldNotLoadThisVendor": "تعذر تحميل هذا البائع.",
  "drivers": "السائقين",
  "ordersNeedAttention": "طلبات تحتاج إلى اهتمام",
  "vendorsToApprove": "بائعون بانتظار الموافقة",
  "noLiveOrdersRightNow": "لا توجد طلبات مباشرة حالياً",
  "useCodeEaty40ToGetThisOffer": "استخدم كود EATY40 للحصول على هذا العرض.",
  "openNow": "مفتوح الآن",
  "closed1": "مغلق",
  "couldNotLoadStores": "تعذر تحميل المتاجر.",
  "noStoresFound": "لم يتم العثور على متاجر",
  "home": "الرئيسية",
  "profile": "الملف الشخصي",
  "required": "مطلوب",
  "addedToCart": "تمت الإضافة إلى السلة",
  "couldNotLoadThisStore": "تعذر تحميل هذا المتجر.",
  "menuComingSoon": "القائمة قريباً",
  "thisStoreIsCurrentlyClosed": "هذا المتجر مغلق حالياً.",
  "subtotal": "المجموع الفرعي",
  "deliveryFee": "رسوم التوصيل",
  "discount": "الخصم",
  "cashOnDelivery": "الدفع عند الاستلام",
  "cardPaymob": "بطاقة · باي موب",
  "yourCartIsEmpty": "سلة التسوق فارغة",
  "noFavoritesYet": "لا توجد مفضلات بعد",
  "favorites": "المفضلة",
  "points": "النقاط",
  "addresses": "العناوين",
  "paymentMethods": "طرق الدفع",
  "settings": "الإعدادات",
  "noAddressesYet": "لا توجد عناوين بعد",
  "locationPermissionDenied": "تم رفض إذن الوصول للموقع",
  "couldNotGetYourLocation": "تعذر تحديد موقعك",
  "yourCartIsEmpty1": "سلة التسوق فارغة",
  "deliveryFee1": "رسوم التوصيل",
  "discount1": "الخصم",
  "total": "الإجمالي",
  "orderNotFound": "الطلب غير موجود.",
  "couldNotStartTheCall": "تعذر بدء المكالمة.",
  "thanksForYourReview": "شكراً لتقييمك!",
  "active2": "نشط",
  "past": "السابقة",
  "rate": "تقييم",
  "reorder": "إعادة طلب",
  "menu": "القائمة",
  "nothingHereRightNow": "لا يوجد شيء هنا حالياً",
  "newOrderReceived": "🔔 تم استلام طلب جديد!",
  "couldNotLoadTheMenu": "تعذر تحميل القائمة.",
  "addASectionThenYourFirstProduct": "أضف قسماً، ثم منتجك الأول",
  "noItemsInThisSectionYet": "لا توجد عناصر في هذا القسم بعد",
  "productSaved": "تم حفظ المنتج",
  "name": "الاسم",
  "description": "الوصف",
  "deliveryFee2": "رسوم التوصيل",
  "minimumOrder": "الحد الأدنى للطلب",
  "minutes": "دقائق",
  "storeName": "اسم المتجر",
  "deliveryFee3": "رسوم التوصيل",
  "minimumOrder1": "الحد الأدنى للطلب",
  "avgPrepTime": "متوسط وقت التحضير",
  "couldNotStartTheCall1": "تعذر بدء المكالمة."
}

def merge_arb(filepath, data_to_merge, is_ar=False):
    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    for k, v in data_to_merge.items():
        # Avoid duplicate keys if already exists, but update if missing
        if k not in data:
            if is_ar:
                data[k] = translations.get(k, v)
            else:
                data[k] = v
                
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def main():
    with open('extracted_extra.json', 'r', encoding='utf-8') as f:
        extra = json.load(f)
        
    merge_arb('lib/l10n/app_en.arb', extra, is_ar=False)
    merge_arb('lib/l10n/app_ar.arb', extra, is_ar=True)
    print("Merged 92 new translated strings into app_en.arb and app_ar.arb.")

if __name__ == '__main__':
    main()

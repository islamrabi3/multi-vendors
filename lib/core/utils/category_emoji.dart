/// Maps a cuisine/category/vendor name to a leading emoji (with trailing
/// space).
///
/// A placeholder for artwork, not a substitute for it: it fills the logo tile
/// of a store that never uploaded one, and the chip of a category with no
/// image. Shared so the home page, the category pages and the cards all guess
/// the same emoji for the same word.
String emojiFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('burger')) return '🍔 ';
  if (n.contains('pizza')) return '🍕 ';
  if (n.contains('sushi') || n.contains('japan')) return '🍣 ';
  if (n.contains('salad') || n.contains('green') || n.contains('healthy')) {
    return '🥗 ';
  }
  if (n.contains('coffee') || n.contains('cafe')) return '☕ ';
  if (n.contains('dessert') || n.contains('sweet') || n.contains('bakery')) {
    return '🍰 ';
  }
  if (n.contains('chicken') || n.contains('fried')) return '🍗 ';
  if (n.contains('drink') || n.contains('juice') || n.contains('beverage')) {
    return '🥤 ';
  }
  if (n.contains('grill') || n.contains('kebab') || n.contains('bbq')) {
    return '🍢 ';
  }
  if (n.contains('fish') || n.contains('seafood')) return '🐟 ';
  if (n.contains('pasta') || n.contains('italian')) return '🍝 ';
  if (n.contains('koshary') || n.contains('egyptian')) return '🍛 ';
  if (n.contains('pharmac') || n.contains('medicine')) return '💊 ';
  if (n.contains('grocer') || n.contains('market') || n.contains('super')) {
    return '🛒 ';
  }
  if (n.contains('store') || n.contains('shop')) return '🏬 ';
  return '🍽️ ';
}

/// Who runs an order between the customer placing it and a rider taking it.
///
/// Set per store, and copied onto each order when it is placed, so switching a
/// store never changes the rules for an order already under way. The server
/// (`update_order_status`, `driver_confirm_pickup`) enforces each one; the app
/// only decides what to show.
enum OrderFlow {
  /// The store is in the app: it accepts, prepares and marks the order ready,
  /// and the rider collects it with the store's pickup code.
  vendor,

  /// The store is not in the app. An operator accepts the order on its
  /// behalf, and accepting it is what sends it to the riders.
  platform,

  /// Nobody accepts. The order goes straight to the riders, and the rider who
  /// takes it buys it at the store and deals with the customer directly.
  direct;

  static OrderFlow fromName(String? name) => switch (name) {
    'platform' => OrderFlow.platform,
    'direct' => OrderFlow.direct,
    _ => OrderFlow.vendor,
  };

  /// Whether the store itself accepts, prepares and hands over.
  bool get runsThroughStore => this == OrderFlow.vendor;
}

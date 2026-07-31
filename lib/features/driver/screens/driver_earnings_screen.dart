import 'package:flutter/material.dart';

class DriverEarningsScreen extends StatelessWidget {
  const DriverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Earnings & Wallet'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.teal, Colors.green]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Today\'s Earnings', style: TextStyle(color: Colors.white70)),
                SizedBox(height: 8),
                Text('450.00 EGP', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Text('Completed Deliveries: 12', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Payout Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Card(
            child: ListTile(
              leading: Icon(Icons.account_balance_wallet, color: Colors.teal),
              title: Text('Available Cash Payout'),
              subtitle: Text('Ready for transfer to your bank account'),
              trailing: Text('380.00 EGP', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
            ),
          ),
        ],
      ),
    );
  }
}

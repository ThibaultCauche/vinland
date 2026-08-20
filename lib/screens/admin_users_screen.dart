import 'package:flutter/material.dart';
import '../models/vinland_user.dart';
import '../services/user_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _userService = UserService();
  List<VinlandUser> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    await _userService.ensureLoaded();
    setState(() {
      _users = _userService.users;
      _isLoading = false;
    });
  }

  String _statusLabel(UserStatus status) {
    switch (status) {
      case UserStatus.pending:
        return 'En attente';
      case UserStatus.approved:
        return 'Approuvé';
      case UserStatus.rejected:
        return 'Refusé';
    }
  }

  Color _statusColor(UserStatus status) {
    switch (status) {
      case UserStatus.pending:
        return Colors.orange;
      case UserStatus.approved:
        return const Color(0xFF1DB954);
      case UserStatus.rejected:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        _users.where((u) => u.status == UserStatus.pending).length;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text('Gestion des utilisateurs',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : Column(
              children: [
                if (pendingCount > 0)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active,
                            color: Colors.orange.withOpacity(0.8)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$pendingCount demande${pendingCount > 1 ? 's' : ''} en attente d\'approbation',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF3E3E3E),
                            child: Text(
                              user.firstName[0].toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            user.fullName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.email,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _statusColor(user.status)
                                      .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _statusLabel(user.status),
                                  style: TextStyle(
                                    color: _statusColor(user.status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: user.status == UserStatus.pending
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check_circle,
                                          color: Color(0xFF1DB954)),
                                      onPressed: () => _approve(user.id),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.cancel,
                                          color: Colors.redAccent),
                                      onPressed: () => _reject(user.id),
                                    ),
                                  ],
                                )
                              : user.isAdmin
                                  ? const Chip(
                                      label: Text('Admin',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10)),
                                      backgroundColor: Color(0xFF1DB954),
                                      padding: EdgeInsets.zero,
                                    )
                                  : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _approve(String userId) async {
    await _userService.approveUser(userId);
    _loadUsers();
  }

  Future<void> _reject(String userId) async {
    await _userService.rejectUser(userId);
    _loadUsers();
  }
}

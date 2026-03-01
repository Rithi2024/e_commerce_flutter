import 'package:marketflow/core/auth/account_role.dart';
import 'package:marketflow/features/admin/domain/entities/admin_profile_model.dart';
import 'package:flutter/material.dart';

class AdminAccountsTab extends StatelessWidget {
  const AdminAccountsTab({
    super.key,
    required this.loadingUsers,
    required this.profiles,
    required this.submitting,
    required this.currentUserId,
    required this.canManageRoles,
    required this.onSetAccountType,
  });

  final bool loadingUsers;
  final List<AdminProfile> profiles;
  final bool submitting;
  final String currentUserId;
  final bool canManageRoles;
  final Future<void> Function(AdminProfile profile, String accountType)
  onSetAccountType;

  @override
  Widget build(BuildContext context) {
    if (loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profiles.isEmpty) {
      return const Center(child: Text('No users found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: profiles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = profiles[index];
        final email = user.email;
        final name = user.name;
        final role = AccountRole.fromRaw(user.accountType);
        final accountType = role.managementValue;
        final isCurrentUser = user.id == currentUserId;
        final canEditRole = canManageRoles && !isCurrentUser && !submitting;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? email : name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(isCurrentUser ? '$email (You)' : email),
                ],
              );

              final rolePicker = SizedBox(
                width: compact ? double.infinity : 180,
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>('account_role_${user.id}_$accountType'),
                  isExpanded: true,
                  initialValue: accountType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  items: AccountRole.orderedAssignableValues
                      .map(
                        (role) => DropdownMenuItem<String>(
                          value: role,
                          child: Text(
                            AccountRole.fromRaw(role).displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: canEditRole
                      ? (value) async {
                          if (value == null || value == accountType) return;
                          await onSetAccountType(user, value);
                        }
                      : null,
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [info, const SizedBox(height: 10), rolePicker],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 12),
                  rolePicker,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

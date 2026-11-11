import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/vault_folder.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/audit_service.dart';
import '../widgets/quick_search_dialog.dart';
import '../widgets/vault_item_card.dart';
import 'audit_screen.dart';
import 'authenticator_screen.dart';
import 'card_editor_screen.dart';
import 'conflicts_screen.dart';
import 'credential_editor_screen.dart';
import 'identity_editor_screen.dart';
import 'import_screen.dart';
import 'license_editor_screen.dart';
import 'note_editor_screen.dart';
import 'secret_editor_screen.dart';
import 'settings_screen.dart';
import 'trash_screen.dart';
import 'wifi_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vault = context.read<VaultProvider>();
      _searchCtrl.text = vault.searchQuery;
      if (vault.allItems.isEmpty && !vault.isLoading) {
        vault.loadVault();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openEditor(VaultItem item) {
    Widget screen;
    switch (item.type) {
      case VaultItemType.note:
        screen = NoteEditorScreen(initialItem: item);
        break;
      case VaultItemType.credential:
        screen = CredentialEditorScreen(initialItem: item);
        break;
      case VaultItemType.card:
        screen = CardEditorScreen(initialItem: item);
        break;
      case VaultItemType.secret:
        screen = SecretEditorScreen(initialItem: item);
        break;
      case VaultItemType.wifi:
        screen = WifiEditorScreen(initialItem: item);
        break;
      case VaultItemType.identity:
        screen = IdentityEditorScreen(initialItem: item);
        break;
      case VaultItemType.license:
        screen = LicenseEditorScreen(initialItem: item);
        break;
      case VaultItemType.folder:
        return;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _createNewItem(VaultItemType type, {String? folderId}) {
    Widget screen;
    switch (type) {
      case VaultItemType.note:
        screen = NoteEditorScreen(initialFolderId: folderId);
        break;
      case VaultItemType.credential:
        screen = CredentialEditorScreen(initialFolderId: folderId);
        break;
      case VaultItemType.card:
        screen = CardEditorScreen(initialFolderId: folderId);
        break;
      case VaultItemType.secret:
        screen = SecretEditorScreen(initialFolderId: folderId);
        break;
      case VaultItemType.wifi:
        screen = WifiEditorScreen(initialFolderId: folderId);
        break;
      case VaultItemType.identity:
        screen = IdentityEditorScreen(initialFolderId: folderId);
        break;
      case VaultItemType.license:
        screen = LicenseEditorScreen(initialFolderId: folderId);
        break;
      case VaultItemType.folder:
        return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _showAddSheet(String? selectedFolderId) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.tr('Yeni Öğe Oluştur', 'Create New Item'),
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _AddTile(
                icon: Icons.description_outlined,
                color: Colors.blueAccent,
                title: l10n.tr('Güvenli Not', 'Secure Note'),
                subtitle: l10n.tr(
                  'Markdown, yapılacak listesi ve şifreli dosya ekleri',
                  'Markdown, checklists & encrypted attachments',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _createNewItem(
                    VaultItemType.note,
                    folderId: selectedFolderId,
                  );
                },
              ),
              _AddTile(
                icon: Icons.vpn_key_outlined,
                color: Colors.teal,
                title: l10n.tr('Hesap & Parola', 'Login & Password'),
                subtitle: l10n.tr(
                  'Web sitesi, kullanıcı adı, parola ve 2FA TOTP',
                  'Website, username, password & 2FA TOTP',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _createNewItem(
                    VaultItemType.credential,
                    folderId: selectedFolderId,
                  );
                },
              ),
              _AddTile(
                icon: Icons.credit_card_outlined,
                color: Colors.indigoAccent,
                title: l10n.tr('Banka / Kredi Kartı', 'Payment Card'),
                subtitle: l10n.tr(
                  'Luhn doğrulama ve son kullanma takibi',
                  'Luhn validation & expiry alerts',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _createNewItem(
                    VaultItemType.card,
                    folderId: selectedFolderId,
                  );
                },
              ),
              _AddTile(
                icon: Icons.wifi_rounded,
                color: Colors.cyan,
                title: l10n.tr('Wi-Fi Ağı', 'Wi-Fi Network'),
                subtitle: l10n.tr(
                  'SSID, parola ve paylaşılabilir Wi-Fi QR kodu',
                  'SSID, passphrase & shareable Wi-Fi QR code',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _createNewItem(
                    VaultItemType.wifi,
                    folderId: selectedFolderId,
                  );
                },
              ),
              _AddTile(
                icon: Icons.badge_outlined,
                color: Colors.deepPurpleAccent,
                title: l10n.tr('Kimlik / Pasaport', 'ID / Passport'),
                subtitle: l10n.tr(
                  'Belge numarası, geçerlilik tarihi ve şifreli belge taraması',
                  'Document number, expiry & encrypted scan attachments',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _createNewItem(
                    VaultItemType.identity,
                    folderId: selectedFolderId,
                  );
                },
              ),
              _AddTile(
                icon: Icons.workspace_premium_outlined,
                color: Colors.amber.shade700,
                title: l10n.tr('Yazılım Lisansı', 'Software License'),
                subtitle: l10n.tr(
                  'Ürün anahtarı, kayıtlı e-posta ve yenileme tarihi',
                  'License key, registered email & renewal date',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _createNewItem(
                    VaultItemType.license,
                    folderId: selectedFolderId,
                  );
                },
              ),
              _AddTile(
                icon: Icons.key_outlined,
                color: Colors.orangeAccent,
                title: l10n.tr('Gizli Anahtar / API', 'API Key / Secret'),
                subtitle: l10n.tr(
                  'Token, kurtarma kelimesi veya gizli anahtar',
                  'Token, recovery phrase or private key',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _createNewItem(
                    VaultItemType.secret,
                    folderId: selectedFolderId,
                  );
                },
              ),
              _AddTile(
                icon: Icons.phonelink_lock_rounded,
                color: Colors.indigoAccent,
                title: l10n.tr(
                  '2FA Doğrulayıcı Kodu / Aktarım',
                  '2FA Authenticator / Import',
                ),
                subtitle: l10n.tr(
                  '30 sn TOTP kodu ekle veya Google Auth / Aegis / 2FAS aktar',
                  'Add 30s TOTP code or migrate from Google Auth / Aegis / 2FAS',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AuthenticatorScreen(
                        openImportOnStart: true,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog(
    VaultProvider vault, {
    String? parentId,
  }) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          parentId == null
              ? l10n.newFolder
              : l10n.tr('Alt Klasör Oluştur', 'Create Subfolder'),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.tr('Klasör Adı', 'Folder Name'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(l10n.add),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (createdName != null && createdName.isNotEmpty) {
      await vault.createFolder(name: createdName, parentId: parentId);
    }
  }

  Future<void> _showRenameFolderDialog(
    VaultProvider vault,
    VaultFolder folder,
  ) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(text: folder.name);
    final updatedName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('Klasörü Yeniden Adlandır', 'Rename Folder')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.tr('Yeni Ad', 'New Name'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (updatedName != null && updatedName.isNotEmpty) {
      await vault.renameFolder(folder.id, updatedName);
    }
  }

  Future<void> _showMoveSelectedDialog(VaultProvider vault) async {
    final l10n = context.l10n;
    String? chosenId = vault.selectedFolderId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            l10n.tr('Seçili Öğeleri Taşı', 'Move Selected Items'),
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(
                      chosenId == null
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: chosenId == null
                          ? Theme.of(ctx).colorScheme.primary
                          : null,
                    ),
                    title: Text(l10n.tr('Klasör Yok (Kök)', 'No Folder (Root)')),
                    onTap: () => setDlg(() => chosenId = null),
                  ),
                  ...vault.folders.map((f) {
                    final selected = chosenId == f.id;
                    return ListTile(
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                      title: Text(f.name),
                      onTap: () => setDlg(() => chosenId = f.id),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.tr('Taşı', 'Move')),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final count = vault.selectedItemIds.length;
      await vault.moveItemsToFolder(vault.selectedItemIds.toList(), chosenId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(
              '$count öğe taşındı.',
              'Moved $count item(s).',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmBulkDelete(VaultProvider vault) async {
    final l10n = context.l10n;
    final inTrash = vault.currentCategory == VaultCategoryFilter.trash;
    final count = vault.selectedItemIds.length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          inTrash
              ? l10n.tr('Kalıcı Olarak Sil', 'Delete Permanently')
              : l10n.tr('Çöp Kutusuna Taşı', 'Move to Trash'),
        ),
        content: Text(
          inTrash
              ? l10n.tr(
                  'Seçili $count öğe kalıcı olarak silinsin mi? Bu işlem geri alınamaz.',
                  'Permanently delete $count selected item(s)? This cannot be undone.',
                )
              : l10n.tr(
                  'Seçili $count öğe çöp kutusuna taşınsın mı?',
                  'Move $count selected item(s) to trash?',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: inTrash
                ? FilledButton.styleFrom(backgroundColor: Colors.redAccent)
                : null,
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (ok == true) {
      final ids = vault.selectedItemIds.toList();
      if (inTrash) {
        await vault.deleteItemsPermanently(ids);
      } else {
        await vault.moveItemsToTrash(ids);
      }
    }
  }

  Widget _buildSidebarContent(
    VaultProvider vault, {
    required bool closeDrawerOnSelect,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final items = vault.items;

    int countFor(VaultCategoryFilter f) {
      switch (f) {
        case VaultCategoryFilter.all:
          return items.length;
        case VaultCategoryFilter.notes:
          return items.where((i) => i.type == VaultItemType.note).length;
        case VaultCategoryFilter.credentials:
          return items.where((i) => i.type == VaultItemType.credential).length;
        case VaultCategoryFilter.cards:
          return items.where((i) => i.type == VaultItemType.card).length;
        case VaultCategoryFilter.secrets:
          return items.where((i) => i.type == VaultItemType.secret).length;
        case VaultCategoryFilter.wifi:
          return items.where((i) => i.type == VaultItemType.wifi).length;
        case VaultCategoryFilter.identity:
          return items.where((i) => i.type == VaultItemType.identity).length;
        case VaultCategoryFilter.license:
          return items.where((i) => i.type == VaultItemType.license).length;
        case VaultCategoryFilter.favorites:
          return items.where((i) => i.isFavorite).length;
        case VaultCategoryFilter.trash:
          return vault.trashItems.length;
      }
    }

    void selectCategory(VaultCategoryFilter f) {
      vault.setCategory(f);
      if (closeDrawerOnSelect && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    void selectFolder(String? folderId) {
      vault.setSelectedFolder(folderId);
      if (closeDrawerOnSelect && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    List<Widget> buildFolderNodes(String? parentId, int depth) {
      final children = vault.folders
          .where((f) => f.parentId == parentId)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final widgets = <Widget>[];
      for (final folder in children) {
        final selected = vault.selectedFolderId == folder.id;
        final descendants = vault.getDescendantFolderIds(folder.id);
        final count = items
            .where((i) => i.folderId != null && descendants.contains(i.folderId))
            .length;

        widgets.add(
          ListTile(
            dense: true,
            selected: selected,
            selectedTileColor: theme.colorScheme.primaryContainer.withValues(
              alpha: 0.45,
            ),
            contentPadding: EdgeInsets.only(
              left: 16.0 + depth * 16.0,
              right: 8,
            ),
            leading: Icon(
              selected ? Icons.folder_open : Icons.folder_outlined,
              size: 19,
            ),
            title: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (count > 0)
                  Text(
                    '$count',
                    style: theme.textTheme.labelSmall,
                  ),
                PopupMenuButton<String>(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  onSelected: (action) {
                    if (action == 'sub') {
                      _showCreateFolderDialog(vault, parentId: folder.id);
                    } else if (action == 'rename') {
                      _showRenameFolderDialog(vault, folder);
                    } else if (action == 'delete') {
                      vault.deleteFolder(folder.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'sub',
                      child: Text(
                        l10n.tr('Alt Klasör Ekle', 'Add Subfolder'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(l10n.tr('Yeniden Adlandır', 'Rename')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(l10n.delete),
                    ),
                  ],
                ),
              ],
            ),
            onTap: () => selectFolder(folder.id),
          ),
        );
        widgets.addAll(buildFolderNodes(folder.id, depth + 1));
      }
      return widgets;
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            l10n.tr('KASA KATEGORİLERİ', 'VAULT CATEGORIES'),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        _SidebarCategoryTile(
          icon: Icons.all_inbox_outlined,
          label: l10n.catAll,
          count: countFor(VaultCategoryFilter.all),
          selected: vault.currentCategory == VaultCategoryFilter.all,
          onTap: () => selectCategory(VaultCategoryFilter.all),
        ),
        _SidebarCategoryTile(
          icon: Icons.star_outline_rounded,
          label: l10n.catFavorites,
          count: countFor(VaultCategoryFilter.favorites),
          selected: vault.currentCategory == VaultCategoryFilter.favorites,
          onTap: () => selectCategory(VaultCategoryFilter.favorites),
        ),
        _SidebarCategoryTile(
          icon: Icons.description_outlined,
          label: l10n.catNotes,
          count: countFor(VaultCategoryFilter.notes),
          selected: vault.currentCategory == VaultCategoryFilter.notes,
          onTap: () => selectCategory(VaultCategoryFilter.notes),
        ),
        _SidebarCategoryTile(
          icon: Icons.vpn_key_outlined,
          label: l10n.catCredentials,
          count: countFor(VaultCategoryFilter.credentials),
          selected: vault.currentCategory == VaultCategoryFilter.credentials,
          onTap: () => selectCategory(VaultCategoryFilter.credentials),
        ),
        _SidebarCategoryTile(
          icon: Icons.credit_card_outlined,
          label: l10n.catCards,
          count: countFor(VaultCategoryFilter.cards),
          selected: vault.currentCategory == VaultCategoryFilter.cards,
          onTap: () => selectCategory(VaultCategoryFilter.cards),
        ),
        _SidebarCategoryTile(
          icon: Icons.wifi_rounded,
          label: l10n.catWifi,
          count: countFor(VaultCategoryFilter.wifi),
          selected: vault.currentCategory == VaultCategoryFilter.wifi,
          onTap: () => selectCategory(VaultCategoryFilter.wifi),
        ),
        _SidebarCategoryTile(
          icon: Icons.badge_outlined,
          label: l10n.catIdentity,
          count: countFor(VaultCategoryFilter.identity),
          selected: vault.currentCategory == VaultCategoryFilter.identity,
          onTap: () => selectCategory(VaultCategoryFilter.identity),
        ),
        _SidebarCategoryTile(
          icon: Icons.workspace_premium_outlined,
          label: l10n.catLicense,
          count: countFor(VaultCategoryFilter.license),
          selected: vault.currentCategory == VaultCategoryFilter.license,
          onTap: () => selectCategory(VaultCategoryFilter.license),
        ),
        _SidebarCategoryTile(
          icon: Icons.key_outlined,
          label: l10n.catSecrets,
          count: countFor(VaultCategoryFilter.secrets),
          selected: vault.currentCategory == VaultCategoryFilter.secrets,
          onTap: () => selectCategory(VaultCategoryFilter.secrets),
        ),
        _SidebarCategoryTile(
          icon: Icons.delete_outline,
          label: l10n.trash,
          count: countFor(VaultCategoryFilter.trash),
          selected: vault.currentCategory == VaultCategoryFilter.trash,
          onTap: () => selectCategory(VaultCategoryFilter.trash),
        ),
        const Divider(height: 16),
        ListTile(
          dense: true,
          leading: const Icon(
            Icons.phonelink_lock_rounded,
            size: 19,
            color: Colors.indigoAccent,
          ),
          title: Text(l10n.authenticator),
          trailing: Builder(
            builder: (_) {
              final totpCount = items
                  .where(
                    (i) =>
                        i.type == VaultItemType.credential &&
                        i.totpSecret.trim().isNotEmpty,
                  )
                  .length;
              return totpCount > 0
                  ? Text('$totpCount', style: theme.textTheme.labelSmall)
                  : const SizedBox.shrink();
            },
          ),
          onTap: () {
            final nav = Navigator.of(context);
            if (closeDrawerOnSelect && nav.canPop()) {
              nav.pop();
            }
            nav.push(
              MaterialPageRoute(builder: (_) => const AuthenticatorScreen()),
            );
          },
        ),
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.folders.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                tooltip: l10n.newFolder,
                onPressed: () => _showCreateFolderDialog(vault),
              ),
            ],
          ),
        ),
        ListTile(
          dense: true,
          selected: vault.selectedFolderId == null,
          leading: const Icon(Icons.folder_special_outlined, size: 19),
          title: Text(l10n.allFolders),
          onTap: () => selectFolder(null),
        ),
        ...buildFolderNodes(null, 0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();
    final vault = context.watch<VaultProvider>();
    final theme = Theme.of(context);

    final auditReport = AuditService.analyzeVault(
      vault.items,
      globalExpiryDays: auth.globalPasswordExpiryDays,
    );

    final folderName = vault.selectedFolderId == null
        ? null
        : vault.folders
            .where((f) => f.id == vault.selectedFolderId)
            .map((f) => f.name)
            .firstOrNull;

    final filtered = vault.filteredItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;

        return Scaffold(
          key: _scaffoldKey,
          drawer: isWide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: _buildSidebarContent(
                      vault,
                      closeDrawerOnSelect: true,
                    ),
                  ),
                ),
          appBar: vault.isSelectionMode
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: vault.clearSelection,
                  ),
                  title: Text(
                    l10n.tr(
                      '${vault.selectedItemIds.length} seçili',
                      '${vault.selectedItemIds.length} selected',
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: l10n.tr('Tümünü Seç', 'Select All'),
                      icon: const Icon(Icons.select_all),
                      onPressed: vault.selectAllFiltered,
                    ),
                    IconButton(
                      tooltip: l10n.tr('Klasöre Taşı', 'Move to Folder'),
                      icon: const Icon(Icons.drive_file_move_outlined),
                      onPressed: () => _showMoveSelectedDialog(vault),
                    ),
                    IconButton(
                      tooltip: l10n.delete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmBulkDelete(vault),
                    ),
                  ],
                )
              : AppBar(
                  title: Row(
                    children: [
                      const Text(
                        'MultiPad',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (folderName != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Chip(
                            avatar: const Icon(Icons.folder_outlined, size: 16),
                            label: Text(
                              folderName,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: () => vault.setSelectedFolder(null),
                          ),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: l10n.authenticator,
                      icon: const Icon(Icons.phonelink_lock_rounded),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AuthenticatorScreen(),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.tr('Hızlı Arama', 'Quick Search'),
                      icon: const Icon(Icons.bolt_rounded),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const QuickSearchDialog(),
                      ),
                    ),
                    if (vault.isOnlineSyncActive)
                      IconButton(
                        tooltip: l10n.tr('Senkronize Et', 'Sync Now'),
                        icon: vault.isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync_rounded),
                        onPressed: vault.isLoading ? null : vault.loadVault,
                      ),
                    IconButton(
                      tooltip: l10n.audit,
                      icon: Badge(
                        isLabelVisible: auditReport.issues.isNotEmpty,
                        label: Text('${auditReport.issues.length}'),
                        child: const Icon(Icons.shield_outlined),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AuditScreen()),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'import':
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ImportScreen(),
                              ),
                            );
                            break;
                          case 'trash':
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TrashScreen(),
                              ),
                            );
                            break;
                          case 'settings':
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                            break;
                          case 'lock':
                            auth.lockVault(reason: 'manual_lock');
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'import',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.file_upload_outlined),
                            title: Text(l10n.importPasswords),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'trash',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.delete_outline),
                            title: Text(
                              '${l10n.trash} (${vault.trashItems.length})',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'settings',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.settings_outlined),
                            title: Text(l10n.settings),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'lock',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.lock_outline),
                            title: Text(l10n.lockVault),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          body: Row(
            children: [
              if (isWide)
                Container(
                  width: 256,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: _buildSidebarContent(
                    vault,
                    closeDrawerOnSelect: false,
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (vault.hasConflicts)
                      MaterialBanner(
                        backgroundColor: Colors.orange.withValues(alpha: 0.14),
                        leading: const Icon(
                          Icons.merge_type,
                          color: Colors.orangeAccent,
                        ),
                        content: Text(
                          l10n.tr(
                            '${vault.conflicts.length} senkronizasyon çakışması bulundu. Veri kaybını önlemek için inceleyin.',
                            '${vault.conflicts.length} sync conflict(s) detected. Review to avoid losing edits.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ConflictsScreen(),
                              ),
                            ),
                            child: Text(l10n.tr('Çöz', 'Resolve')),
                          ),
                        ],
                      ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: vault.setSearchQuery,
                        decoration: InputDecoration(
                          hintText: l10n.search,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    vault.setSearchQuery('');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),

                    if (!isWide)
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            _CategoryChip(
                              label: l10n.catAll,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.all,
                              onTap: () =>
                                  vault.setCategory(VaultCategoryFilter.all),
                            ),
                            _CategoryChip(
                              label: l10n.catCredentials,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.credentials,
                              onTap: () => vault.setCategory(
                                VaultCategoryFilter.credentials,
                              ),
                            ),
                            _CategoryChip(
                              label: l10n.catNotes,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.notes,
                              onTap: () =>
                                  vault.setCategory(VaultCategoryFilter.notes),
                            ),
                            _CategoryChip(
                              label: l10n.catCards,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.cards,
                              onTap: () =>
                                  vault.setCategory(VaultCategoryFilter.cards),
                            ),
                            _CategoryChip(
                              label: l10n.catWifi,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.wifi,
                              onTap: () =>
                                  vault.setCategory(VaultCategoryFilter.wifi),
                            ),
                            _CategoryChip(
                              label: l10n.catIdentity,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.identity,
                              onTap: () => vault.setCategory(
                                VaultCategoryFilter.identity,
                              ),
                            ),
                            _CategoryChip(
                              label: l10n.catLicense,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.license,
                              onTap: () => vault.setCategory(
                                VaultCategoryFilter.license,
                              ),
                            ),
                            _CategoryChip(
                              label: l10n.catSecrets,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.secrets,
                              onTap: () => vault.setCategory(
                                VaultCategoryFilter.secrets,
                              ),
                            ),
                            _CategoryChip(
                              label: l10n.catFavorites,
                              selected:
                                  vault.currentCategory ==
                                  VaultCategoryFilter.favorites,
                              onTap: () => vault.setCategory(
                                VaultCategoryFilter.favorites,
                              ),
                            ),
                          ],
                        ),
                      ),

                    Expanded(
                      child: vault.isLoading && filtered.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : filtered.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.lock_open_rounded,
                                          size: 56,
                                          color: theme.colorScheme.outline,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          l10n.tr(
                                            'Bu görünümde henüz öğe yok.',
                                            'No items in this view yet.',
                                          ),
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          l10n.tr(
                                            'Sağ alttaki + düğmesiyle yeni not, parola, Wi-Fi veya kimlik ekleyin.',
                                            'Tap + below to add a note, password, Wi-Fi or ID card.',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    6,
                                    12,
                                    88,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (ctx, idx) {
                                    final item = filtered[idx];
                                    final isSelected = vault.selectedItemIds
                                        .contains(item.id);
                                    return VaultItemCard(
                                      item: item,
                                      isSelectionMode: vault.isSelectionMode,
                                      isSelected: isSelected,
                                      onLongPress: () =>
                                          vault.enterSelectionMode(item.id),
                                      onTap: () {
                                        if (vault.isSelectionMode) {
                                          vault.toggleSelection(item.id);
                                        } else {
                                          _openEditor(item);
                                        }
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: vault.isSelectionMode
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _showAddSheet(vault.selectedFolderId),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.tr('Yeni Öğe', 'New Item')),
                ),
        );
      },
    );
  }
}

class _SidebarCategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarCategoryTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.45,
      ),
      leading: Icon(icon, size: 19),
      title: Text(label),
      trailing: count > 0
          ? Text(
              '$count',
              style: theme.textTheme.labelSmall,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.16),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

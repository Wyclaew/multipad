import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../widgets/vault_item_card.dart';
import 'audit_screen.dart';
import 'backup_screen.dart';
import 'card_editor_screen.dart';
import 'credential_editor_screen.dart';
import 'note_editor_screen.dart';
import 'secret_editor_screen.dart';
import 'settings_screen.dart';
import 'trash_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openNoteEditor([VaultItem? item]) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(initialItem: item)));
  }

  void _openCredentialEditor([VaultItem? item]) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CredentialEditorScreen(initialItem: item)));
  }

  void _openCardEditor([VaultItem? item]) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardEditorScreen(initialItem: item)));
  }

  void _openSecretEditor([VaultItem? item]) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SecretEditorScreen(initialItem: item)));
  }

  void _showAddModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Yeni Şifreli Öğe Ekle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ListTile(
                  leading: _buildIconBox(Icons.description_outlined, Colors.blueAccent),
                  title: const Text('Yeni Not', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Kişisel notlar, yapılacaklar ve metinler'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openNoteEditor();
                  },
                ),
                ListTile(
                  leading: _buildIconBox(Icons.vpn_key_outlined, Colors.purpleAccent),
                  title: const Text('Yeni Şifre / Hesap', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Web sitesi, kullanıcı adı, şifre ve 2FA TOTP'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openCredentialEditor();
                  },
                ),
                ListTile(
                  leading: _buildIconBox(Icons.credit_card_outlined, Colors.orangeAccent),
                  title: const Text('Banka / Kredi Kartı', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Kart no, SKT, CVV ve PIN kodları'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openCardEditor();
                  },
                ),
                ListTile(
                  leading: _buildIconBox(Icons.security_outlined, Colors.tealAccent),
                  title: const Text('Gizli Anahtar / Token', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('SSH anahtarları, API tokenları, tohum kelimeleri'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openSecretEditor();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIconBox(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 22),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final auth = context.watch<AuthProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _openNoteEditor,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _openNoteEditor,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true): _openCredentialEditor,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): _openCredentialEditor,
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () => auth.lockVault(),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => auth.lockVault(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => _searchFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocusNode.requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield_rounded, size: 20, color: Colors.blueAccent),
                ),
                const SizedBox(width: 10),
                const Text('MultiPad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
                if (!vault.isOnlineSyncActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 12, color: Colors.amber),
                        SizedBox(width: 4),
                        Text('Yerel Kasa (E2EE)', style: TextStyle(fontSize: 10, color: Colors.amber)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              // Security Audit
              IconButton(
                icon: const Icon(Icons.health_and_safety_outlined),
                tooltip: 'Parola Güvenlik Denetimi',
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuditScreen()));
                },
              ),
              // Encrypted Backup
              IconButton(
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'Şifreli Yedekleme',
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupScreen()));
                },
              ),
              // Quick Lock Button
              IconButton(
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Kasayı Kilitle (Cmd+L)',
                onPressed: () => auth.lockVault(),
              ),
              // Settings Button
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Ayarlar',
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          floatingActionButton: isDesktop
              ? null
              : FloatingActionButton.extended(
                  onPressed: _showAddModal,
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Ekle'),
                ),
          body: Row(
            children: [
              // Desktop Sidebar
              if (isDesktop) ...[
                SizedBox(
                  width: 250,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6)),
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Yeni Ekle'),
                          onPressed: _showAddModal,
                        ),
                        const SizedBox(height: 20),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Text('KATEGORİLER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        _buildSidebarTile(
                          icon: Icons.inventory_2_outlined,
                          label: 'Tüm Öğeler',
                          category: VaultCategoryFilter.all,
                          current: vault.currentCategory,
                          onTap: () => vault.setCategory(VaultCategoryFilter.all),
                        ),
                        _buildSidebarTile(
                          icon: Icons.description_outlined,
                          label: 'Notlar',
                          category: VaultCategoryFilter.notes,
                          current: vault.currentCategory,
                          onTap: () => vault.setCategory(VaultCategoryFilter.notes),
                        ),
                        _buildSidebarTile(
                          icon: Icons.vpn_key_outlined,
                          label: 'Şifreler & Hesaplar',
                          category: VaultCategoryFilter.credentials,
                          current: vault.currentCategory,
                          onTap: () => vault.setCategory(VaultCategoryFilter.credentials),
                        ),
                        _buildSidebarTile(
                          icon: Icons.credit_card_outlined,
                          label: 'Banka Kartları',
                          category: VaultCategoryFilter.cards,
                          current: vault.currentCategory,
                          onTap: () => vault.setCategory(VaultCategoryFilter.cards),
                        ),
                        _buildSidebarTile(
                          icon: Icons.security_outlined,
                          label: 'Gizli Anahtarlar',
                          category: VaultCategoryFilter.secrets,
                          current: vault.currentCategory,
                          onTap: () => vault.setCategory(VaultCategoryFilter.secrets),
                        ),
                        _buildSidebarTile(
                          icon: Icons.star_outline_rounded,
                          label: 'Favoriler',
                          category: VaultCategoryFilter.favorites,
                          current: vault.currentCategory,
                          onTap: () => vault.setCategory(VaultCategoryFilter.favorites),
                        ),
                        const Divider(height: 24),
                        _buildSidebarTile(
                          icon: Icons.delete_outline_rounded,
                          label: 'Çöp Kutusu',
                          category: VaultCategoryFilter.trash,
                          current: vault.currentCategory,
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashScreen()));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Main Items List
              Expanded(
                child: Column(
                  children: [
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: SearchBar(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        hintText: 'Şifreli notlarda, kartlarda ve hesaplarda ara...',
                        leading: const Padding(
                          padding: EdgeInsets.only(left: 8.0),
                          child: Icon(Icons.search, size: 20),
                        ),
                        trailing: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                vault.setSearchQuery('');
                              },
                            ),
                        ],
                        onChanged: (val) => vault.setSearchQuery(val),
                        elevation: const MaterialStatePropertyAll(0),
                        side: MaterialStatePropertyAll(
                          BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                      ),
                    ),

                    // Mobile Filter Chips
                    if (!isDesktop)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            _buildFilterChip('Tümü', VaultCategoryFilter.all, vault),
                            const SizedBox(width: 8),
                            _buildFilterChip('Notlar', VaultCategoryFilter.notes, vault),
                            const SizedBox(width: 8),
                            _buildFilterChip('Şifreler', VaultCategoryFilter.credentials, vault),
                            const SizedBox(width: 8),
                            _buildFilterChip('Kartlar', VaultCategoryFilter.cards, vault),
                            const SizedBox(width: 8),
                            _buildFilterChip('Gizli', VaultCategoryFilter.secrets, vault),
                            const SizedBox(width: 8),
                            _buildFilterChip('Favoriler', VaultCategoryFilter.favorites, vault),
                          ],
                        ),
                      ),

                    const SizedBox(height: 6),

                    // List View
                    Expanded(
                      child: vault.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : vault.filteredItems.isEmpty
                              ? _buildEmptyState(context, isDesktop)
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 80),
                                  itemCount: vault.filteredItems.length,
                                  itemBuilder: (ctx, i) {
                                    final item = vault.filteredItems[i];
                                    return VaultItemCard(
                                      item: item,
                                      onTap: () {
                                        switch (item.type) {
                                          case VaultItemType.credential:
                                            _openCredentialEditor(item);
                                            break;
                                          case VaultItemType.card:
                                            _openCardEditor(item);
                                            break;
                                          case VaultItemType.secret:
                                            _openSecretEditor(item);
                                            break;
                                          case VaultItemType.note:
                                          default:
                                            _openNoteEditor(item);
                                            break;
                                        }
                                      },
                                      onToggleFavorite: () => vault.toggleFavorite(item),
                                      onTogglePin: () => vault.togglePin(item),
                                      onMoveToTrash: () => vault.moveToTrash(item),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VaultCategoryFilter cat, VaultProvider vault) {
    return FilterChip(
      label: Text(label),
      selected: vault.currentCategory == cat,
      onSelected: (_) => vault.setCategory(cat),
    );
  }

  Widget _buildSidebarTile({
    required IconData icon,
    required String label,
    required VaultCategoryFilter category,
    required VaultCategoryFilter current,
    required VoidCallback onTap,
  }) {
    final isSelected = category == current;
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      selected: isSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDesktop) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 64, color: Colors.grey.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            'Kasanızda Henüz Öğe Yok',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Eklediğiniz tüm notlar, kartlar ve şifreler cihazınızda anında\nAES-256 ile şifrelenir ve sıfır-bilgi güvenliğiyle saklanır.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _showAddModal,
            icon: const Icon(Icons.add),
            label: const Text('İlk Öğenizi Ekleyin'),
          ),
        ],
      ),
    );
  }
}

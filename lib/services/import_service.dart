import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import '../models/vault_folder.dart';
import '../models/vault_item.dart';

enum ImportSourceFormat {
  autoDetect,
  chromeEdgeCsv,
  bitwardenCsv,
  bitwardenJson,
  keepassCsv,
  keepassXml,
  genericCsv,
}

class CsvColumnMapping {
  int? titleIndex;
  int? usernameIndex;
  int? passwordIndex;
  int? websiteIndex;
  int? totpIndex;
  int? notesIndex;
  int? folderIndex;

  CsvColumnMapping({
    this.titleIndex,
    this.usernameIndex,
    this.passwordIndex,
    this.websiteIndex,
    this.totpIndex,
    this.notesIndex,
    this.folderIndex,
  });
}

class ParsedImportPreview {
  final ImportSourceFormat detectedFormat;
  final List<String> headers;
  final List<List<String>> rows;
  final CsvColumnMapping suggestedMapping;
  final List<VaultItem> directParsedItems;
  final List<VaultFolder> directParsedFolders;

  const ParsedImportPreview({
    required this.detectedFormat,
    required this.headers,
    required this.rows,
    required this.suggestedMapping,
    this.directParsedItems = const [],
    this.directParsedFolders = const [],
  });
}

class ImportService {
  static const _uuid = Uuid();

  /// Parses an RFC-4180 CSV string safely handling quoted newlines, embedded commas, and escaped double quotes.
  static List<List<String>> parseCsvRows(String rawContent) {
    var content = rawContent;
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1); // Strip UTF-8 BOM
    }
    if (content.trim().isEmpty) return [];

    // Detect delimiter (',' vs ';') from first line outside quotes
    final delimiter = _detectDelimiter(content);

    final List<List<String>> rows = [];
    List<String> currentRow = [];
    final StringBuffer cell = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < content.length; i++) {
      final ch = content[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == delimiter) {
          currentRow.add(cell.toString());
          cell.clear();
        } else if (ch == '\r') {
          if (i + 1 < content.length && content[i + 1] == '\n') i++;
          currentRow.add(cell.toString());
          cell.clear();
          rows.add(currentRow);
          currentRow = [];
        } else if (ch == '\n') {
          currentRow.add(cell.toString());
          cell.clear();
          rows.add(currentRow);
          currentRow = [];
        } else {
          cell.write(ch);
        }
      }
    }

    if (cell.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(cell.toString());
      rows.add(currentRow);
    }

    return rows
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
  }

  static String _detectDelimiter(String content) {
    var inQuotes = false;
    var commas = 0;
    var semicolons = 0;
    for (int i = 0; i < content.length; i++) {
      final ch = content[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes) {
        if (ch == '\n' || ch == '\r') break;
        if (ch == ',') commas++;
        if (ch == ';') semicolons++;
      }
    }
    return semicolons > commas ? ';' : ',';
  }

  /// Inspects raw file contents (CSV, Bitwarden JSON, KeePass XML) and prepares preview + auto-mapped columns.
  static ParsedImportPreview inspectFile(
    String rawContent, {
    String fileName = '',
    ImportSourceFormat formatHint = ImportSourceFormat.autoDetect,
  }) {
    final trimmed = rawContent.trimLeft();
    final lowerName = fileName.toLowerCase();

    if (formatHint == ImportSourceFormat.bitwardenJson ||
        (formatHint == ImportSourceFormat.autoDetect &&
            (lowerName.endsWith('.json') || trimmed.startsWith('{')))) {
      final parsed = _parseBitwardenJson(rawContent);
      return ParsedImportPreview(
        detectedFormat: ImportSourceFormat.bitwardenJson,
        headers: const ['Başlık', 'Kullanıcı', 'URL', 'Tür'],
        rows: parsed.items
            .take(50)
            .map((e) => [e.title, e.username, e.website, e.type.storageKey])
            .toList(),
        suggestedMapping: CsvColumnMapping(
          titleIndex: 0,
          usernameIndex: 1,
          websiteIndex: 2,
        ),
        directParsedItems: parsed.items,
        directParsedFolders: parsed.folders,
      );
    }

    if (formatHint == ImportSourceFormat.keepassXml ||
        (formatHint == ImportSourceFormat.autoDetect &&
            (lowerName.endsWith('.xml') || trimmed.startsWith('<')))) {
      final parsed = _parseKeePassXml(rawContent);
      return ParsedImportPreview(
        detectedFormat: ImportSourceFormat.keepassXml,
        headers: const ['Başlık', 'Kullanıcı', 'URL', 'Not'],
        rows: parsed.items
            .take(50)
            .map((e) => [e.title, e.username, e.website, e.content])
            .toList(),
        suggestedMapping: CsvColumnMapping(
          titleIndex: 0,
          usernameIndex: 1,
          websiteIndex: 2,
          notesIndex: 3,
        ),
        directParsedItems: parsed.items,
        directParsedFolders: parsed.folders,
      );
    }

    final csvRows = parseCsvRows(rawContent);
    if (csvRows.isEmpty) {
      throw Exception('Dosya boş veya okunabilir kayıt bulunamadı.');
    }

    final headers = csvRows.first.map((h) => h.trim()).toList();
    final dataRows = csvRows.length > 1 ? csvRows.sublist(1) : <List<String>>[];

    final lowerHeaders = headers.map((h) => h.toLowerCase()).toList();
    ImportSourceFormat detected = formatHint;
    if (detected == ImportSourceFormat.autoDetect) {
      if (lowerHeaders.contains('login_uri') ||
          lowerHeaders.contains('login_username') ||
          lowerHeaders.contains('login_password')) {
        detected = ImportSourceFormat.bitwardenCsv;
      } else if (lowerHeaders.contains('group') ||
          lowerHeaders.contains('account') ||
          lowerHeaders.contains('login name')) {
        detected = ImportSourceFormat.keepassCsv;
      } else if (lowerHeaders.contains('name') &&
          lowerHeaders.contains('url') &&
          lowerHeaders.contains('username')) {
        detected = ImportSourceFormat.chromeEdgeCsv;
      } else {
        detected = ImportSourceFormat.genericCsv;
      }
    }

    final mapping = _guessMapping(lowerHeaders);
    return ParsedImportPreview(
      detectedFormat: detected,
      headers: headers,
      rows: dataRows,
      suggestedMapping: mapping,
    );
  }

  static CsvColumnMapping _guessMapping(List<String> lowerHeaders) {
    int? findMatch(List<String> candidates) {
      for (final c in candidates) {
        final exact = lowerHeaders.indexOf(c);
        if (exact != -1) return exact;
      }
      for (int i = 0; i < lowerHeaders.length; i++) {
        for (final c in candidates) {
          if (lowerHeaders[i].contains(c)) return i;
        }
      }
      return null;
    }

    return CsvColumnMapping(
      titleIndex: findMatch(['name', 'title', 'account', 'başlık', 'ad', 'site']),
      usernameIndex: findMatch(
          ['login_username', 'username', 'login name', 'user', 'email', 'kullanıcı']),
      passwordIndex:
          findMatch(['login_password', 'password', 'pass', 'şifre', 'parola']),
      websiteIndex: findMatch(['login_uri', 'url', 'web site', 'website', 'uri']),
      totpIndex: findMatch(['login_totp', 'totp', '2fa', 'otp']),
      notesIndex: findMatch(['notes', 'note', 'comments', 'extra', 'not']),
      folderIndex: findMatch(['folder', 'group', 'klasör', 'kategori']),
    );
  }

  /// Materializes mapped CSV rows or directly parsed JSON/XML entries into MultiPad [VaultItem]s & [VaultFolder]s.
  static ({List<VaultItem> items, List<VaultFolder> folders}) buildItemsFromPreview(
    ParsedImportPreview preview,
    CsvColumnMapping mapping,
  ) {
    if (preview.directParsedItems.isNotEmpty) {
      return (
        items: preview.directParsedItems,
        folders: preview.directParsedFolders,
      );
    }

    final folderMap = <String, VaultFolder>{};
    final items = <VaultItem>[];

    String? cell(List<String> row, int? idx) {
      if (idx == null || idx < 0 || idx >= row.length) return null;
      return row[idx].trim();
    }

    for (final row in preview.rows) {
      final rawTitle = cell(row, mapping.titleIndex) ?? '';
      final username = cell(row, mapping.usernameIndex) ?? '';
      final password = cell(row, mapping.passwordIndex) ?? '';
      final website = cell(row, mapping.websiteIndex) ?? '';
      final totp = cell(row, mapping.totpIndex) ?? '';
      final notes = cell(row, mapping.notesIndex) ?? '';
      final folderName = cell(row, mapping.folderIndex) ?? '';

      if (rawTitle.isEmpty &&
          username.isEmpty &&
          password.isEmpty &&
          website.isEmpty &&
          notes.isEmpty) {
        continue;
      }

      String? folderId;
      if (folderName.isNotEmpty) {
        final folder = folderMap.putIfAbsent(
          folderName,
          () => VaultFolder(
            id: _uuid.v4(),
            name: folderName,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        folderId = folder.id;
      }

      final title = rawTitle.isNotEmpty
          ? rawTitle
          : (website.isNotEmpty
              ? website
              : (username.isNotEmpty ? username : 'İçe Aktarılan Kayıt'));

      final isNoteOnly =
          password.isEmpty && username.isEmpty && website.isEmpty;

      items.add(
        VaultItem(
          id: _uuid.v4(),
          type: isNoteOnly ? VaultItemType.note : VaultItemType.credential,
          title: title,
          content: notes,
          username: username,
          password: password,
          website: website,
          totpSecret: totp,
          folderId: folderId,
          tags: const ['İçe Aktarıldı'],
          passwordLastModified:
              password.isNotEmpty ? DateTime.now().toUtc() : null,
          clientUpdatedAt: DateTime.now().toUtc(),
        ),
      );
    }

    return (items: items, folders: folderMap.values.toList());
  }

  static ({List<VaultItem> items, List<VaultFolder> folders}) _parseBitwardenJson(
    String rawJson,
  ) {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final rawFolders = (decoded['folders'] as List<dynamic>?) ?? const [];
    final rawItems = (decoded['items'] as List<dynamic>?) ?? const [];

    final folders = <VaultFolder>[];
    final folderIdMap = <String, String>{};
    for (final f in rawFolders) {
      if (f is! Map) continue;
      final oldId = f['id']?.toString();
      final name = f['name']?.toString().trim() ?? '';
      if (oldId != null && name.isNotEmpty) {
        final newId = _uuid.v4();
        folderIdMap[oldId] = newId;
        folders.add(VaultFolder(
          id: newId,
          name: name,
          updatedAt: DateTime.now().toUtc(),
        ));
      }
    }

    final items = <VaultItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final name = m['name']?.toString() ?? 'İçe Aktarılan Kayıt';
      final notes = m['notes']?.toString() ?? '';
      final bwType = m['type'] as int? ?? 1;
      final favorite = m['favorite'] as bool? ?? false;
      final oldFolder = m['folderId']?.toString();
      final folderId = oldFolder != null ? folderIdMap[oldFolder] : null;

      final customFields = <CustomField>[];
      for (final cf in (m['fields'] as List<dynamic>? ?? const [])) {
        if (cf is! Map) continue;
        customFields.add(CustomField(
          id: _uuid.v4(),
          label: cf['name']?.toString() ?? 'Alan',
          value: cf['value']?.toString() ?? '',
          isHidden: (cf['type'] as int? ?? 0) == 1,
        ));
      }

      if (bwType == 1) {
        final login =
            Map<String, dynamic>.from(m['login'] as Map? ?? const {});
        final uris = login['uris'] as List<dynamic>? ?? const [];
        final website = uris.isNotEmpty && uris.first is Map
            ? (uris.first['uri']?.toString() ?? '')
            : '';
        final pass = login['password']?.toString() ?? '';
        items.add(VaultItem(
          id: _uuid.v4(),
          type: VaultItemType.credential,
          title: name,
          content: notes,
          username: login['username']?.toString() ?? '',
          password: pass,
          website: website,
          totpSecret: login['totp']?.toString() ?? '',
          folderId: folderId,
          isFavorite: favorite,
          customFields: customFields,
          tags: const ['Bitwarden'],
          passwordLastModified:
              pass.isNotEmpty ? DateTime.now().toUtc() : null,
          clientUpdatedAt: DateTime.now().toUtc(),
        ));
      } else if (bwType == 3) {
        final card = Map<String, dynamic>.from(m['card'] as Map? ?? const {});
        final expMonth = card['expMonth']?.toString().padLeft(2, '0') ?? '';
        var expYear = card['expYear']?.toString() ?? '';
        if (expYear.length == 4) expYear = expYear.substring(2);
        items.add(VaultItem(
          id: _uuid.v4(),
          type: VaultItemType.card,
          title: name,
          content: notes,
          cardNumber: card['number']?.toString() ?? '',
          cardHolder: card['cardholderName']?.toString() ?? '',
          cardExpiry:
              (expMonth.isNotEmpty && expYear.isNotEmpty) ? '$expMonth/$expYear' : '',
          cardCvv: card['code']?.toString() ?? '',
          folderId: folderId,
          isFavorite: favorite,
          customFields: customFields,
          tags: const ['Bitwarden'],
          clientUpdatedAt: DateTime.now().toUtc(),
        ));
      } else if (bwType == 4) {
        final idMap =
            Map<String, dynamic>.from(m['identity'] as Map? ?? const {});
        items.add(VaultItem(
          id: _uuid.v4(),
          type: VaultItemType.identity,
          title: name,
          content: notes,
          fullName: [
            idMap['firstName']?.toString() ?? '',
            idMap['lastName']?.toString() ?? '',
          ].where((e) => e.isNotEmpty).join(' '),
          idNumber: idMap['passportNumber']?.toString() ??
              idMap['ssn']?.toString() ??
              '',
          folderId: folderId,
          isFavorite: favorite,
          customFields: customFields,
          tags: const ['Bitwarden'],
          clientUpdatedAt: DateTime.now().toUtc(),
        ));
      } else {
        items.add(VaultItem(
          id: _uuid.v4(),
          type: VaultItemType.note,
          title: name,
          content: notes,
          folderId: folderId,
          isFavorite: favorite,
          customFields: customFields,
          tags: const ['Bitwarden'],
          clientUpdatedAt: DateTime.now().toUtc(),
        ));
      }
    }

    return (items: items, folders: folders);
  }

  static ({List<VaultItem> items, List<VaultFolder> folders}) _parseKeePassXml(
    String rawXml,
  ) {
    final doc = XmlDocument.parse(rawXml);
    final folders = <VaultFolder>[];
    final items = <VaultItem>[];

    void walkGroup(XmlElement groupEl, String? parentFolderId) {
      final groupName = groupEl
              .getElement('Name')
              ?.innerText
              .trim() ??
          '';
      String? currentFolderId = parentFolderId;
      if (groupName.isNotEmpty &&
          groupName.toLowerCase() != 'root' &&
          groupName.toLowerCase() != 'recycle bin') {
        final folder = VaultFolder(
          id: _uuid.v4(),
          name: groupName,
          parentId: parentFolderId,
          updatedAt: DateTime.now().toUtc(),
        );
        folders.add(folder);
        currentFolderId = folder.id;
      }

      for (final entry in groupEl.findElements('Entry')) {
        String title = '';
        String username = '';
        String password = '';
        String website = '';
        String notes = '';
        for (final strEl in entry.findElements('String')) {
          final k = strEl.getElement('Key')?.innerText ?? '';
          final v = strEl.getElement('Value')?.innerText ?? '';
          switch (k) {
            case 'Title':
              title = v;
              break;
            case 'UserName':
              username = v;
              break;
            case 'Password':
              password = v;
              break;
            case 'URL':
              website = v;
              break;
            case 'Notes':
              notes = v;
              break;
          }
        }
        items.add(VaultItem(
          id: _uuid.v4(),
          type: VaultItemType.credential,
          title: title.isNotEmpty ? title : (website.isNotEmpty ? website : 'KeePass'),
          username: username,
          password: password,
          website: website,
          content: notes,
          folderId: currentFolderId,
          tags: const ['KeePass'],
          passwordLastModified:
              password.isNotEmpty ? DateTime.now().toUtc() : null,
          clientUpdatedAt: DateTime.now().toUtc(),
        ));
      }

      for (final subGroup in groupEl.findElements('Group')) {
        walkGroup(subGroup, currentFolderId);
      }
    }

    final rootGroup = doc.rootElement.getElement('Root')?.getElement('Group');
    if (rootGroup != null) {
      walkGroup(rootGroup, null);
    }
    return (items: items, folders: folders);
  }
}

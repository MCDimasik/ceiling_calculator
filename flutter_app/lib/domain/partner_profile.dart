import 'documentation_model.dart';

/// Requisites of the subcontractor (ИП Гусев) — default stamp filler.
class PartnerProfile {
  const PartnerProfile({
    required this.legalName,
    required this.shortName,
    required this.inn,
    required this.kpp,
    required this.ogrn,
    required this.okved,
    required this.legalAddress,
    required this.phone,
    required this.email,
    required this.bankName,
    required this.bankAccount,
    required this.bankBik,
    required this.bankCorrAccount,
    required this.executorLine,
    required this.okpo,
  });

  final String legalName;
  final String shortName;
  final String inn;
  final String kpp;
  final String ogrn;
  final String okved;
  final String legalAddress;
  final String phone;
  final String email;
  final String bankName;
  final String bankAccount;
  final String bankBik;
  final String bankCorrAccount;

  /// Single-line «Подрядчик» for KS-2 header.
  final String executorLine;
  final String okpo;

  /// Default profile from partner card (ИП Гусев И.Д.).
  static const defaultGusev = PartnerProfile(
    legalName: 'Индивидуальный предприниматель Гусев Илья Дмитриевич',
    shortName: 'ИП Гусев И.Д.',
    inn: '344107788410',
    kpp: '344402001',
    ogrn: '324344300075045',
    okved: '41.20',
    legalAddress:
        '400125, Волгоградская обл., г. Волгоград, ул. Грамши, д. 43, кв. 36',
    phone: '8-988-782-47-22',
    email: 'Gusew2456@yandex.ru',
    bankName: 'АО «Тинькофф Банк»',
    bankAccount: '408028104110000074241',
    bankBik: '041806647',
    bankCorrAccount: '30101810100000000647',
    executorLine:
        'ИП Гусев И.Д., г. Волгоград, ул. Грамши, д. 43, кв. 36, т/ф 8 988 982 47 22',
    okpo: '',
  );

  DocumentationStamp applyToStamp(DocumentationStamp stamp) {
    return stamp.copyWith(
      executor: executorLine,
      designer: stamp.designer.isEmpty ? shortName : stamp.designer,
    );
  }

  ProjectContractInfo applyToContract(ProjectContractInfo contract) {
    return contract;
  }

  /// Typical Авангард customer (name ≠ address — stamp fields are separate).
  static const avangardCustomer = (
    name: 'ООО «ГК Авангард»',
    address: '400074, г. Волгоград, ул. им. Менделеева, д. 43, офис 23',
    okpo: '2034109678',
    inn: '',
  );

  /// Legacy one-line fill that put address into «Заказчик».
  static const avangardCustomerLegacyLine =
      'ООО «ГК Авангард», 400074, г. Волгоград, ул. им. Менделеева, д. 43, офис 23';
}

/// Universal split: «ООО „…“, 400074, г. …» → name + address when address empty.
/// Also handles legacy Avangard one-liner and «Name, г. Город, ул. …» without index.
(String name, String address)? splitOrgNameAndAddress(String combined) {
  final text = combined.trim();
  if (text.isEmpty) return null;

  // Postal index: ", 400074" / ",400074"
  final byIndex = RegExp(r',\s*(\d{6}\b.*)$').firstMatch(text);
  if (byIndex != null) {
    final name = text.substring(0, byIndex.start).trim();
    final address = byIndex.group(1)!.trim();
    if (name.isNotEmpty && address.isNotEmpty) return (name, address);
  }

  // City marker without index: ", г. Волгоград…" / ", город …"
  final byCity = RegExp(
    r',\s*((?:г\.|город|пос\.|пгт\.|с\.|дер\.)\s+.+)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (byCity != null) {
    final name = text.substring(0, byCity.start).trim();
    final address = byCity.group(1)!.trim();
    if (name.isNotEmpty && address.isNotEmpty) return (name, address);
  }

  return null;
}

/// Split legacy «Заказчик + адрес в одной строке» into stamp.customer / stamp.address.
void normalizeStampCustomerAddress(DocumentationStamp stamp) {
  final customer = stamp.customer.trim();
  if (customer.isEmpty || stamp.address.trim().isNotEmpty) return;
  final split = splitOrgNameAndAddress(customer);
  if (split == null) return;
  stamp.customer = split.$1;
  stamp.address = split.$2;
}

void normalizeContractCustomerAddress(ProjectContractInfo contract) {
  final name = contract.customerName.trim();
  if (name.isEmpty || contract.buildSite.trim().isNotEmpty) return;
  final split = splitOrgNameAndAddress(name);
  if (split == null) return;
  contract.customerName = split.$1;
  contract.buildSite = split.$2;
}

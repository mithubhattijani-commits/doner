// Doner Society — directory data, mirrored from the society website
// (~/workspace/aman-blood/dist/index.html). No donor records are bundled:
// the website's live donor list lives in its Cloudflare KV store, so the
// app shows the directory structure with honest empty states instead.

/// Province (Urdu) -> districts (Urdu), same order as the website.
const Map<String, List<String>> districts = {
  'پنجاب': ['اٹک', 'بہاولنگر', 'بہاولپور', 'بھکر', 'چکوال', 'چنیوٹ', 'ڈیرہ غازی خان', 'فیصل آباد', 'گوجرانوالہ', 'گجرات', 'حافظ آباد', 'جھنگ', 'جہلم', 'قصور', 'خانیوال', 'خوشاب', 'لاہور', 'لیہ', 'لودھراں', 'منڈی بہاؤالدین', 'میانوالی', 'ملتان', 'مظفر گڑھ', 'کوٹ ادو', 'نارووال', 'ننکانہ صاحب', 'اوکاڑہ', 'پاکپتن', 'رحیم یار خان', 'راجن پور', 'راولپنڈی', 'ساہیوال', 'سرگودھا', 'شیخوپورہ', 'سیالکوٹ', 'ٹوبہ ٹیک سنگھ', 'وہاڑی', 'مری', 'تلہ گنگ', 'وزیر آباد', 'تونسہ'],
  'سندھ': ['کراچی وسطی', 'کراچی شرقی', 'کراچی جنوبی', 'کراچی غربی', 'کیماڑی', 'کورنگی', 'ملیر', 'حیدرآباد', 'دادو', 'جامشورو', 'مٹیاری', 'ٹنڈو الہ یار', 'ٹنڈو محمد خان', 'بدین', 'سجاول', 'ٹھٹھہ', 'سکھر', 'گھوٹکی', 'خیرپور', 'لاڑکانہ', 'قمبر شہدادکوٹ', 'شکارپور', 'جیکب آباد', 'کشمور', 'میرپور خاص', 'عمرکوٹ', 'تھرپارکر', 'سانگھڑ', 'شہید بینظیر آباد', 'نوشہرو فیروز'],
  'خیبر پختونخوا': ['پشاور', 'مردان', 'صوابی', 'چارسدہ', 'نوشہرہ', 'کوہاٹ', 'ہنگو', 'کرک', 'بنوں', 'لکی مروت', 'ڈیرہ اسماعیل خان', 'ٹانک', 'ایبٹ آباد', 'ہری پور', 'مانسہرہ', 'بٹگرام', 'تورغر', 'کوہستان بالا', 'کوہستان زیریں', 'شانگلہ', 'سوات', 'بونیر', 'مالاکنڈ', 'دیر بالا', 'دیر زیریں', 'چترال بالا', 'چترال زیریں', 'باجوڑ', 'مہمند', 'خیبر', 'کرم', 'اورکزئی', 'شمالی وزیرستان', 'جنوبی وزیرستان'],
  'بلوچستان': ['کوئٹہ', 'پشین', 'قلعہ عبداللہ', 'چمن', 'قلعہ سیف اللہ', 'ژوب', 'لورالائی', 'دکی', 'موسیٰ خیل', 'بارکھان', 'سبی', 'ہرنائی', 'زیارت', 'قلات', 'مستونگ', 'خضدار', 'آواران', 'واشک', 'خاران', 'نوشکی', 'چاغی', 'پنجگور', 'کیچ (تربت)', 'گوادر', 'لسبیلہ', 'حب', 'جعفرآباد', 'نصیرآباد', 'صحبت پور', 'جھل مگسی', 'کچھ (بولان)', 'ڈیرہ بگٹی', 'کوہلو', 'شیرانی'],
  'گلگت بلتستان': ['گلگت', 'غذر', 'ہنزہ', 'نگر', 'سکردو', 'شگر', 'کھرمنگ', 'گانچھے', 'استور', 'دیامر'],
  'آزاد کشمیر': ['مظفرآباد', 'ہٹیاں بالا', 'نیلم', 'میرپور', 'بھمبر', 'کوٹلی', 'پونچھ', 'سدھنوتی', 'باغ', 'حویلی'],
  'اسلام آباد': ['اسلام آباد'],
};

/// District -> known areas/tehsils (only districts the website lists areas
/// for; other districts show their donor list / empty state directly).
const Map<String, List<String>> areas = {
  'شیخوپورہ': ['شیخوپورہ سٹی', 'فیروز والہ', 'مریدکے', 'شرقپور شریف', 'صفدرآباد', 'مانانوالہ', 'فاروق آباد', 'خانقاہ ڈوگراں', 'جنڈیالہ شیر خان'],
  'لاہور': ['گلبرگ', 'ماڈل ٹاؤن', 'جوہر ٹاؤن', 'ڈیفنس (DHA)', 'والٹن', 'شالیمار', 'راوی ٹاؤن', 'داتا گنج بخش ٹاؤن', 'اقبال ٹاؤن', 'سبزہ زار', 'واہگہ ٹاؤن', 'نشتر ٹاؤن'],
  'کراچی وسطی': ['ناظم آباد', 'نیو کراچی', 'لیاقت آباد', 'گلبرگ (کراچی)', 'فیڈرل بی ایریا'],
  'اسلام آباد': ['ایف سیکٹرز', 'جی سیکٹرز', 'آئی سیکٹرز', 'بھارہ کہو', 'ترنول', 'رورل ایریا'],
};

/// Blood groups offered by the directory (website order).
const List<String> bloodGroups = ['O+', 'O\u2212', 'A+', 'A\u2212', 'B+', 'B\u2212', 'AB+', 'AB\u2212'];

/// Donor group -> patient groups it can donate to (red-cell compatibility,
/// from the website's compatibility table).
const Map<String, List<String>> canDonateTo = {
  'O\u2212': ['O+', 'O\u2212', 'A+', 'A\u2212', 'B+', 'B\u2212', 'AB+', 'AB\u2212'],
  'O+': ['O+', 'A+', 'B+', 'AB+'],
  'A\u2212': ['A\u2212', 'A+', 'AB\u2212', 'AB+'],
  'A+': ['A+', 'AB+'],
  'B\u2212': ['B\u2212', 'B+', 'AB\u2212', 'AB+'],
  'B+': ['B+', 'AB+'],
  'AB\u2212': ['AB\u2212', 'AB+'],
  'AB+': ['AB+'],
};

/// Patient group -> donor groups it can receive from (reverse of the table).
Map<String, List<String>> get canReceiveFrom {
  final Map<String, List<String>> out = {for (final g in bloodGroups) g: []};
  canDonateTo.forEach((donor, recipients) {
    for (final r in recipients) {
      out[r]!.add(donor);
    }
  });
  return out;
}

/// Urdu district -> the English district name the Worker API uses.
/// GET /api/incharges/:district validates the district against the
/// Worker's own English list and answers "bad district" for an Urdu
/// name, so the app translates before calling it. Standard
/// transliterations; a district the server spells differently simply has
/// no in-charge card (the lookup fails soft, nothing is shown).
const Map<String, String> districtEnglish = {
  'اٹک': 'Attock',
  'بہاولنگر': 'Bahawalnagar',
  'بہاولپور': 'Bahawalpur',
  'بھکر': 'Bhakkar',
  'چکوال': 'Chakwal',
  'چنیوٹ': 'Chiniot',
  'ڈیرہ غازی خان': 'Dera Ghazi Khan',
  'فیصل آباد': 'Faisalabad',
  'گوجرانوالہ': 'Gujranwala',
  'گجرات': 'Gujrat',
  'حافظ آباد': 'Hafizabad',
  'جھنگ': 'Jhang',
  'جہلم': 'Jhelum',
  'قصور': 'Kasur',
  'خانیوال': 'Khanewal',
  'خوشاب': 'Khushab',
  'لاہور': 'Lahore',
  'لیہ': 'Layyah',
  'لودھراں': 'Lodhran',
  'منڈی بہاؤالدین': 'Mandi Bahauddin',
  'میانوالی': 'Mianwali',
  'ملتان': 'Multan',
  'مظفر گڑھ': 'Muzaffargarh',
  'کوٹ ادو': 'Kot Addu',
  'نارووال': 'Narowal',
  'ننکانہ صاحب': 'Nankana Sahib',
  'اوکاڑہ': 'Okara',
  'پاکپتن': 'Pakpattan',
  'رحیم یار خان': 'Rahim Yar Khan',
  'راجن پور': 'Rajanpur',
  'راولپنڈی': 'Rawalpindi',
  'ساہیوال': 'Sahiwal',
  'سرگودھا': 'Sargodha',
  'شیخوپورہ': 'Sheikhupura',
  'سیالکوٹ': 'Sialkot',
  'ٹوبہ ٹیک سنگھ': 'Toba Tek Singh',
  'وہاڑی': 'Vehari',
  'مری': 'Murree',
  'تلہ گنگ': 'Talagang',
  'وزیر آباد': 'Wazirabad',
  'تونسہ': 'Taunsa',
  'کراچی وسطی': 'Karachi Central',
  'کراچی شرقی': 'Karachi East',
  'کراچی جنوبی': 'Karachi South',
  'کراچی غربی': 'Karachi West',
  'کیماڑی': 'Keamari',
  'کورنگی': 'Korangi',
  'ملیر': 'Malir',
  'حیدرآباد': 'Hyderabad',
  'دادو': 'Dadu',
  'جامشورو': 'Jamshoro',
  'مٹیاری': 'Matiari',
  'ٹنڈو الہ یار': 'Tando Allahyar',
  'ٹنڈو محمد خان': 'Tando Muhammad Khan',
  'بدین': 'Badin',
  'سجاول': 'Sujawal',
  'ٹھٹھہ': 'Thatta',
  'سکھر': 'Sukkur',
  'گھوٹکی': 'Ghotki',
  'خیرپور': 'Khairpur',
  'لاڑکانہ': 'Larkana',
  'قمبر شہدادکوٹ': 'Qambar Shahdadkot',
  'شکارپور': 'Shikarpur',
  'جیکب آباد': 'Jacobabad',
  'کشمور': 'Kashmore',
  'میرپور خاص': 'Mirpur Khas',
  'عمرکوٹ': 'Umerkot',
  'تھرپارکر': 'Tharparkar',
  'سانگھڑ': 'Sanghar',
  'شہید بینظیر آباد': 'Shaheed Benazirabad',
  'نوشہرو فیروز': 'Naushahro Feroze',
  'پشاور': 'Peshawar',
  'مردان': 'Mardan',
  'صوابی': 'Swabi',
  'چارسدہ': 'Charsadda',
  'نوشہرہ': 'Nowshera',
  'کوہاٹ': 'Kohat',
  'ہنگو': 'Hangu',
  'کرک': 'Karak',
  'بنوں': 'Bannu',
  'لکی مروت': 'Lakki Marwat',
  'ڈیرہ اسماعیل خان': 'Dera Ismail Khan',
  'ٹانک': 'Tank',
  'ایبٹ آباد': 'Abbottabad',
  'ہری پور': 'Haripur',
  'مانسہرہ': 'Mansehra',
  'بٹگرام': 'Battagram',
  'تورغر': 'Torghar',
  'کوہستان بالا': 'Upper Kohistan',
  'کوہستان زیریں': 'Lower Kohistan',
  'شانگلہ': 'Shangla',
  'سوات': 'Swat',
  'بونیر': 'Buner',
  'مالاکنڈ': 'Malakand',
  'دیر بالا': 'Upper Dir',
  'دیر زیریں': 'Lower Dir',
  'چترال بالا': 'Upper Chitral',
  'چترال زیریں': 'Lower Chitral',
  'باجوڑ': 'Bajaur',
  'مہمند': 'Mohmand',
  'خیبر': 'Khyber',
  'کرم': 'Kurram',
  'اورکزئی': 'Orakzai',
  'شمالی وزیرستان': 'North Waziristan',
  'جنوبی وزیرستان': 'South Waziristan',
  'کوئٹہ': 'Quetta',
  'پشین': 'Pishin',
  'قلعہ عبداللہ': 'Killa Abdullah',
  'چمن': 'Chaman',
  'قلعہ سیف اللہ': 'Killa Saifullah',
  'ژوب': 'Zhob',
  'لورالائی': 'Loralai',
  'دکی': 'Dukki',
  'موسیٰ خیل': 'Musakhel',
  'بارکھان': 'Barkhan',
  'سبی': 'Sibi',
  'ہرنائی': 'Harnai',
  'زیارت': 'Ziarat',
  'قلات': 'Kalat',
  'مستونگ': 'Mastung',
  'خضدار': 'Khuzdar',
  'آواران': 'Awaran',
  'واشک': 'Washuk',
  'خاران': 'Kharan',
  'نوشکی': 'Nushki',
  'چاغی': 'Chagai',
  'پنجگور': 'Panjgur',
  'کیچ (تربت)': 'Kech',
  'گوادر': 'Gwadar',
  'لسبیلہ': 'Lasbela',
  'حب': 'Hub',
  'جعفرآباد': 'Jaffarabad',
  'نصیرآباد': 'Naseerabad',
  'صحبت پور': 'Sohbatpur',
  'جھل مگسی': 'Jhal Magsi',
  'کچھ (بولان)': 'Kachhi',
  'ڈیرہ بگٹی': 'Dera Bugti',
  'کوہلو': 'Kohlu',
  'شیرانی': 'Sherani',
  'گلگت': 'Gilgit',
  'غذر': 'Ghizer',
  'ہنزہ': 'Hunza',
  'نگر': 'Nagar',
  'سکردو': 'Skardu',
  'شگر': 'Shigar',
  'کھرمنگ': 'Kharmang',
  'گانچھے': 'Ghanche',
  'استور': 'Astore',
  'دیامر': 'Diamer',
  'مظفرآباد': 'Muzaffarabad',
  'ہٹیاں بالا': 'Hattian Bala',
  'نیلم': 'Neelum',
  'میرپور': 'Mirpur',
  'بھمبر': 'Bhimber',
  'کوٹلی': 'Kotli',
  'پونچھ': 'Poonch',
  'سدھنوتی': 'Sudhanoti',
  'باغ': 'Bagh',
  'حویلی': 'Haveli',
  'اسلام آباد': 'Islamabad',
};

/// English (Worker) name for an Urdu district; returns the input unchanged
/// when it is not in [districtEnglish] (already English or unknown).
String districtEnglishName(String urduDistrict) =>
    districtEnglish[urduDistrict] ?? urduDistrict;

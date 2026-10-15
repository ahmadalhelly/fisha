import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// One report: a title and a table. Built into DOCX (a hand-made zip of XML) or PDF (pages drawn by Flutter, so Arabic
/// text is shaped correctly, then wrapped in a minimal PDF), with no extra packages.
class ReportTable {
  final String title, subtitle;
  final List<String> header;
  final List<List<String>> rows;
  final List<String> total;
  final List<double> widths; // column shares, sum 1
  final bool rtl;
  const ReportTable({
    required this.title,
    required this.subtitle,
    required this.header,
    required this.rows,
    required this.total,
    required this.widths,
    required this.rtl,
  });
}

// ---------------------------------------------------------------- shared
int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

void _u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
void _u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

// ---------------------------------------------------------------- DOCX
String _x(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

Uint8List buildDocx(ReportTable t) {
  String para(String text, {bool bold = false, int size = 22, bool center = false}) =>
      '<w:p><w:pPr>${t.rtl ? '<w:bidi/>' : ''}${center ? '<w:jc w:val="center"/>' : ''}</w:pPr><w:r><w:rPr>${bold ? '<w:b/><w:bCs/>' : ''}'
      '<w:sz w:val="$size"/><w:szCs w:val="$size"/>${t.rtl ? '<w:rtl/>' : ''}</w:rPr><w:t xml:space="preserve">${_x(text)}</w:t></w:r></w:p>';
  String cell(String text, int w, {bool bold = false, String? fill}) =>
      '<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}</w:tcPr>${para(text, bold: bold, size: 20)}</w:tc>';
  const total = 9400;
  final ws = [for (final w in t.widths) (w * total).round()];
  String row(List<String> cells, {bool bold = false, String? fill}) =>
      '<w:tr>${[for (var i = 0; i < cells.length; i++) cell(cells[i], ws[i], bold: bold, fill: fill)].join()}</w:tr>';
  final tbl = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="$total" w:type="dxa"/>${t.rtl ? '<w:bidiVisual/>' : ''}<w:tblBorders>'
      '<w:top w:val="single" w:sz="4" w:color="999999"/><w:left w:val="single" w:sz="4" w:color="999999"/>'
      '<w:bottom w:val="single" w:sz="4" w:color="999999"/><w:right w:val="single" w:sz="4" w:color="999999"/>'
      '<w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/></w:tblBorders></w:tblPr>'
      '<w:tblGrid>${[for (final w in ws) '<w:gridCol w:w="$w"/>'].join()}</w:tblGrid>');
  tbl.write(row(t.header, bold: true, fill: 'D9EFE8'));
  for (final r in t.rows) {
    tbl.write(row(r));
  }
  tbl.write(row(t.total, bold: true, fill: 'F0F0F0'));
  tbl.write('</w:tbl>');
  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
      '${para(t.title, bold: true, size: 36)}${para(t.subtitle, size: 20)}$tbl'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1200" w:bottom="1000" w:left="1200" w:header="500" w:footer="500" w:gutter="0"/></w:sectPr>'
      '</w:body></w:document>';
  const types = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';
  const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';
  return _zip({'[Content_Types].xml': utf8.encode(types), '_rels/.rels': utf8.encode(rels), 'word/document.xml': utf8.encode(doc)});
}

/// A zip with stored (uncompressed) entries.
Uint8List _zip(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  files.forEach((name, data) {
    final n = utf8.encode(name);
    final crc = _crc32(data);
    final offset = out.length;
    _u32(out, 0x04034b50);
    _u16(out, 20);
    _u16(out, 0x0800); // utf-8 names
    _u16(out, 0);
    _u16(out, 0);
    _u16(out, 0x21);
    _u32(out, crc);
    _u32(out, data.length);
    _u32(out, data.length);
    _u16(out, n.length);
    _u16(out, 0);
    out.add(n);
    out.add(data);
    _u32(central, 0x02014b50);
    _u16(central, 20);
    _u16(central, 20);
    _u16(central, 0x0800);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0x21);
    _u32(central, crc);
    _u32(central, data.length);
    _u32(central, data.length);
    _u16(central, n.length);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, 0);
    _u32(central, offset);
    central.add(n);
    count++;
  });
  final start = out.length;
  final c = central.toBytes();
  out.add(c);
  _u32(out, 0x06054b50);
  _u16(out, 0);
  _u16(out, 0);
  _u16(out, count);
  _u16(out, count);
  _u32(out, c.length);
  _u32(out, start);
  _u16(out, 0);
  return out.toBytes();
}

// ---------------------------------------------------------------- PDF
const _pw = 794.0, _ph = 1123.0, _scale = 1.25; // A4 at 96 dpi, drawn at 120 dpi
const _margin = 44.0, _rowH = 26.0;

TextPainter _tp(String text, double size, Color color, bool rtl, {bool bold = false, double? maxW, TextAlign align = TextAlign.start}) {
  final p = TextPainter(
    text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  );
  p.layout(minWidth: maxW ?? 0, maxWidth: maxW ?? double.infinity);
  return p;
}

Future<Uint8List> buildPdf(ReportTable t) async {
  final usable = _ph - _margin * 2;
  final first = ((usable - 90) / _rowH).floor();
  final other = (usable / _rowH).floor();
  final pages = <List<List<String>>>[];
  final all = [...t.rows, t.total];
  var i = 0;
  while (i < all.length) {
    final cap = pages.isEmpty ? first : other;
    pages.add(all.sublist(i, (i + cap).clamp(0, all.length)));
    i += cap;
  }
  final grays = <Uint8List>[];
  for (var pi = 0; pi < pages.length; pi++) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, _pw * _scale, _ph * _scale));
    c.scale(_scale);
    c.drawRect(const Rect.fromLTWH(0, 0, _pw, _ph), Paint()..color = const Color(0xFFFFFFFF));
    var y = _margin;
    final colW = [for (final w in t.widths) w * (_pw - _margin * 2)];
    if (pi == 0) {
      final tt = _tp(t.title, 22, const Color(0xFF000000), t.rtl, bold: true, maxW: _pw - _margin * 2);
      tt.paint(c, Offset(_margin, y));
      y += 32;
      final st = _tp(t.subtitle, 12, const Color(0xFF555555), t.rtl, maxW: _pw - _margin * 2);
      st.paint(c, Offset(_margin, y));
      y += 38;
    }
    void drawRow(List<String> cells, {bool bold = false, Color? fill}) {
      if (fill != null) c.drawRect(Rect.fromLTWH(_margin, y, _pw - _margin * 2, _rowH), Paint()..color = fill);
      // columns run right-to-left in Arabic, left-to-right otherwise
      var x = t.rtl ? _pw - _margin : _margin;
      for (var k = 0; k < cells.length; k++) {
        final w = colW[k];
        final left = t.rtl ? x - w : x;
        final p = _tp(cells[k], 12, const Color(0xFF111111), t.rtl, bold: bold, maxW: w - 12);
        p.paint(c, Offset(left + 6, y + (_rowH - p.height) / 2));
        x += t.rtl ? -w : w;
      }
      c.drawLine(Offset(_margin, y + _rowH), Offset(_pw - _margin, y + _rowH), Paint()..color = const Color(0xFFDDDDDD)..strokeWidth = 0.7);
      y += _rowH;
    }

    drawRow(t.header, bold: true, fill: const Color(0xFFD9EFE8));
    final rows = pages[pi];
    for (final r in rows) {
      final isTotal = identical(r, t.total);
      drawRow(r, bold: isTotal, fill: isTotal ? const Color(0xFFF0F0F0) : null);
    }
    final pg = _tp('${pi + 1} / ${pages.length}', 10, const Color(0xFF888888), false, maxW: 80, align: TextAlign.center);
    pg.paint(c, Offset((_pw - 80) / 2, _ph - 30));
    final img = await rec.endRecording().toImage((_pw * _scale).round(), (_ph * _scale).round());
    final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final px = data.buffer.asUint8List();
    final w = img.width, h = img.height;
    final gray = Uint8List(w * h);
    for (var q = 0, o = 0; q < gray.length; q++, o += 4) {
      gray[q] = ((px[o] * 77 + px[o + 1] * 151 + px[o + 2] * 28) >> 8).clamp(0, 255);
    }
    grays.add(gray);
  }
  return _pdfFromGray(grays, (_pw * _scale).round(), (_ph * _scale).round());
}

/// zlib stream made of stored blocks (no compression): header, blocks of up to 65535 bytes, Adler-32.
Uint8List _zlibStored(Uint8List d) {
  final b = BytesBuilder();
  b.add([0x78, 0x01]);
  var a = 1, s2 = 0;
  for (final v in d) {
    a = (a + v) % 65521;
    s2 = (s2 + a) % 65521;
  }
  var p = 0;
  while (p < d.length || p == 0) {
    final n = (d.length - p) > 65535 ? 65535 : d.length - p;
    final last = p + n >= d.length;
    b.add([last ? 1 : 0, n & 0xFF, (n >> 8) & 0xFF, ~n & 0xFF, (~n >> 8) & 0xFF]);
    b.add(Uint8List.sublistView(d, p, p + n));
    p += n;
    if (last) break;
  }
  final ad = (s2 << 16) | a;
  b.add([(ad >> 24) & 0xFF, (ad >> 16) & 0xFF, (ad >> 8) & 0xFF, ad & 0xFF]);
  return b.toBytes();
}

Uint8List _pdfFromGray(List<Uint8List> pages, int w, int h) {
  final out = BytesBuilder();
  final offsets = <int>[];
  void obj(int n, List<int> body) {
    while (offsets.length < n) {
      offsets.add(0);
    }
    offsets[n - 1] = out.length;
    out.add(ascii.encode('$n 0 obj\n'));
    out.add(body);
    out.add(ascii.encode('\nendobj\n'));
  }

  out.add(ascii.encode('%PDF-1.4\n'));
  final np = pages.length;
  // 1 catalog, 2 pages, then per page: page, content, image
  obj(1, ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'));
  obj(2, ascii.encode('<< /Type /Pages /Count $np /Kids [${[for (var i = 0; i < np; i++) '${3 + i * 3} 0 R'].join(' ')}] >>'));
  for (var i = 0; i < np; i++) {
    final base = 3 + i * 3;
    obj(base, ascii.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /XObject << /Im0 ${base + 2} 0 R >> >> /Contents ${base + 1} 0 R >>'));
    final content = ascii.encode('q 595 0 0 842 0 0 cm /Im0 Do Q');
    obj(base + 1, [...ascii.encode('<< /Length ${content.length} >>\nstream\n'), ...content, ...ascii.encode('\nendstream')]);
    final z = _zlibStored(pages[i]);
    obj(base + 2, [
      ...ascii.encode('<< /Type /XObject /Subtype /Image /Width $w /Height $h /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length ${z.length} >>\nstream\n'),
      ...z,
      ...ascii.encode('\nendstream')
    ]);
  }
  final xref = out.length;
  final n = offsets.length + 1;
  final sb = StringBuffer('xref\n0 $n\n0000000000 65535 f \n');
  for (final o in offsets) {
    sb.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  sb.write('trailer\n<< /Size $n /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  out.add(ascii.encode(sb.toString()));
  return out.toBytes();
}

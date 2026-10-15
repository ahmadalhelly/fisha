package com.mttlhub.mttl_hub

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import android.widget.Toast
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Home-screen widgets. The app writes one JSON ("widget_json"); everything below is drawn natively from it. */
object FishaWidgets {
    const val PREFS = "HomeWidgetPreferences"
    const val ACTION_TOGGLE = "com.fisha.app.WIDGET_TOGGLE"

    private val MUTED = Color.parseColor("#8798B3")
    private val SOFT = Color.parseColor("#C2D1E8")
    private val TEXT = Color.parseColor("#E9F2FF")
    private val FAINT = Color.parseColor("#4D5C77")
    private val ACCENT = Color.parseColor("#2EE6B0")
    private val ORANGE = Color.parseColor("#FF9F43")
    private val RED = Color.parseColor("#FF5470")
    private val BORDER = Color.parseColor("#22314F")

    fun data(ctx: Context): JSONObject = try {
        JSONObject(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("widget_json", "{}") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    fun saveData(ctx: Context, j: JSONObject) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("widget_json", j.toString()).apply()
    }

    fun updateAll(ctx: Context) {
        val mgr = AppWidgetManager.getInstance(ctx)
        val mainIds = mgr.getAppWidgetIds(ComponentName(ctx, FishaWidgetProvider::class.java))
        if (mainIds.isNotEmpty()) FishaWidgetProvider().onUpdate(ctx, mgr, mainIds)
        val stripIds = mgr.getAppWidgetIds(ComponentName(ctx, FishaStripWidgetProvider::class.java))
        if (stripIds.isNotEmpty()) FishaStripWidgetProvider().onUpdate(ctx, mgr, stripIds)
    }

    fun openApp(ctx: Context, id: Int): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java)
        return PendingIntent.getActivity(ctx, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun sizeDp(mgr: AppWidgetManager, id: Int, defW: Float, defH: Float): Pair<Float, Float> {
        val o: Bundle? = mgr.getAppWidgetOptions(id)
        val w = o?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
        val h = o?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
        return Pair(if (w > 40) w.toFloat() else defW, if (h > 40) h.toFloat() else defH)
    }

    fun bitmap(ctx: Context, wDp: Float, hDp: Float, draw: (Canvas, Float, Float) -> Unit): Bitmap {
        var sc = ctx.resources.displayMetrics.density
        val maxPx = 900f
        if (wDp * sc > maxPx) sc = maxPx / wDp
        if (hDp * sc > maxPx) sc = minOf(sc, maxPx / hDp)
        val bmp = Bitmap.createBitmap(maxOf(1, (wDp * sc).toInt()), maxOf(1, (hDp * sc).toInt()), Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.scale(sc, sc)
        draw(c, wDp, hDp)
        return bmp
    }

    // ---------------- drawing helpers ----------------

    private fun col(s: String?, def: Int): Int = try { Color.parseColor(s) } catch (e: Exception) { def }

    private fun paint(color: Int, size: Float = 12f, bold: Boolean = false, style: Paint.Style = Paint.Style.FILL): Paint {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.color = color
        p.textSize = size
        p.style = style
        if (bold) p.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        return p
    }

    private fun tempColor(t: Int): Int = if (t >= 70) RED else if (t >= 50) ORANGE else SOFT

    private fun fmt(n: Int): String = String.format(java.util.Locale.US, "%,d", n)

    /** RTL-aware drawing: offsets are measured from the start edge (right in Arabic, left in English). */
    private class Dr(val c: Canvas, val w: Float, val h: Float, val rtl: Boolean) {
        fun xs(d: Float) = if (rtl) w - d else d
        fun xe(d: Float) = if (rtl) d else w - d
        fun textS(s: String, d: Float, y: Float, p: Paint) {
            p.textAlign = if (rtl) Paint.Align.RIGHT else Paint.Align.LEFT
            c.drawText(s, xs(d), y, p)
        }
        fun textE(s: String, d: Float, y: Float, p: Paint) {
            p.textAlign = if (rtl) Paint.Align.LEFT else Paint.Align.RIGHT
            c.drawText(s, xe(d), y, p)
        }
        fun rectS(d: Float, width: Float, top: Float, bottom: Float): RectF =
            if (rtl) RectF(w - d - width, top, w - d, bottom) else RectF(d, top, d + width, bottom)
        /** label + value as one group starting [d] from the start edge */
        fun pair(d: Float, y: Float, label: String, value: String, lp: Paint, vp: Paint): Float {
            val lw = lp.measureText(label)
            val vw = vp.measureText(value)
            textS(label, d, y, lp)
            textS(value, d + lw + 4f, y, vp)
            return lw + 4f + vw
        }
        fun pairWidth(label: String, value: String, lp: Paint, vp: Paint): Float = lp.measureText(label) + 4f + vp.measureText(value)
    }

    private fun thermo(c: Canvas, cx: Float, cy: Float, color: Int) {
        val p = paint(color, 1f, false, Paint.Style.STROKE)
        p.strokeWidth = 1.5f
        p.strokeCap = Paint.Cap.ROUND
        c.drawLine(cx, cy - 5f, cx, cy + 2f, p)
        val f = paint(color)
        c.drawCircle(cx, cy + 3.5f, 2.6f, f)
    }

    // ---------------- main widget "أ": total, temperature, graph, strip bars ----------------

    fun drawMain(c: Canvas, w: Float, h: Float, j: JSONObject) {
        val rtl = j.optBoolean("ar", true)
        val d = Dr(c, w, h, rtl)
        val bg = paint(Color.BLACK)
        bg.shader = LinearGradient(0f, 0f, w, h, Color.parseColor("#0F1A30"), Color.parseColor("#0B1324"), Shader.TileMode.CLAMP)
        c.drawRoundRect(RectF(0f, 0f, w, h), 22f, 22f, bg)
        val bd = paint(BORDER, 1f, false, Paint.Style.STROKE)
        c.drawRoundRect(RectF(0.5f, 0.5f, w - 0.5f, h - 0.5f), 22f, 22f, bd)
        val strips = j.optJSONArray("strips")
        if (strips == null || strips.length() == 0) {
            val p = paint(MUTED, 13f)
            p.textAlign = Paint.Align.CENTER
            c.drawText(j.optString("l_none", "Fisha"), w / 2, h / 2, p)
            return
        }
        val pad = 15f
        d.textS(j.optString("l_now"), pad, pad + 10f, paint(MUTED, 12f))
        val big = paint(TEXT, 34f, true)
        val num = fmt(j.optInt("total"))
        d.textS(num, pad, pad + 44f, big)
        d.textS("W", pad + big.measureText(num) + 4f, pad + 44f, paint(MUTED, 15f))
        // status (mode) and the hottest temperature, at the end edge
        val mode = j.optString("mode")
        val mp = paint(MUTED, 11f)
        d.textE(mode, pad, pad + 10f, mp)
        val dot = paint(ACCENT)
        c.drawCircle(d.xe(pad + mp.measureText(mode) + 9f), pad + 6.5f, 3.2f, dot)
        val hot = j.optInt("hot")
        val ht = hot.toString() + "°C"
        val hp = paint(tempColor(hot), 12f, true)
        val chipW = hp.measureText(ht) + 30f
        val chipR = if (rtl) RectF(pad, pad + 20f, pad + chipW, pad + 40f) else RectF(w - pad - chipW, pad + 20f, w - pad, pad + 40f)
        c.drawRoundRect(chipR, 10f, 10f, paint(Color.parseColor("#1A2640")))
        thermo(c, if (rtl) chipR.left + 11f else chipR.left + 11f, chipR.centerY() - 2.5f, tempColor(hot))
        hp.textAlign = Paint.Align.LEFT
        c.drawText(ht, chipR.left + 19f, chipR.centerY() + 4.2f, hp)

        val n = minOf(strips.length(), 4)
        val barRow = 18f
        val footH = 22f
        val top = pad + 52f
        val gapSum = 14f
        val gH = (h - top - n * barRow - footH - pad - gapSum).coerceIn(14f, 70f)
        // graph
        val hist = j.optJSONArray("hist")
        val pts = ArrayList<Float>()
        if (hist != null) for (i in 0 until hist.length()) pts.add(hist.optDouble(i, 0.0).toFloat())
        if (pts.size < 2) { pts.clear(); pts.add(0f); pts.add(0f) }
        val mx = (pts.maxOrNull() ?: 1f) * 1.1f + 1f
        val mn = (pts.minOrNull() ?: 0f) * 0.8f
        val gl = pad
        val gr = w - pad
        val line = Path()
        for (i in pts.indices) {
            val px = gl + (gr - gl) * i / (pts.size - 1)
            val py = top + gH - ((pts[i] - mn) / (mx - mn).coerceAtLeast(1f)) * (gH - 4f)
            if (i == 0) line.moveTo(px, py) else line.lineTo(px, py)
        }
        val area = Path(line)
        area.lineTo(gr, top + gH)
        area.lineTo(gl, top + gH)
        area.close()
        val fill = paint(Color.BLACK)
        fill.shader = LinearGradient(0f, top, 0f, top + gH, Color.argb(90, 46, 230, 176), Color.argb(0, 46, 230, 176), Shader.TileMode.CLAMP)
        c.drawPath(area, fill)
        val lp = paint(ACCENT, 1f, false, Paint.Style.STROKE)
        lp.strokeWidth = 1.8f
        lp.strokeJoin = Paint.Join.ROUND
        c.drawPath(line, lp)
        // one bar per strip
        var y = top + gH + 10f
        val nameP = paint(SOFT, 12f)
        val wP = paint(MUTED, 11f)
        val trackW = (w - 2 * pad - 78f - 94f).coerceAtLeast(20f)
        for (i in 0 until n) {
            val s = strips.getJSONObject(i)
            val on = s.optBoolean("on", true)
            val sw = s.optInt("w")
            d.textS(s.optString("name"), pad, y + 12f, nameP)
            val tr = d.rectS(pad + 78f, trackW, y + 5f, y + 11f)
            c.drawRoundRect(tr, 3f, 3f, paint(Color.parseColor("#1A2640")))
            val ratio = (sw / 3500f).coerceIn(0f, 1f)
            val fc = if (!on) FAINT else if (ratio >= 0.9f) RED else if (ratio >= 0.7f) ORANGE else col(s.optString("c"), ACCENT)
            val fw = maxOf(3f, trackW * ratio)
            c.drawRoundRect(d.rectS(pad + 78f, fw, y + 5f, y + 11f), 3f, 3f, paint(fc))
            d.textS(if (on) fmt(sw) + " W" else "—", pad + 78f + trackW + 8f, y + 11f, wP)
            val tp = paint(if (on) tempColor(s.optInt("t")) else FAINT, 11f)
            d.textS(if (on) s.optInt("t").toString() + "°" else "", pad + 78f + trackW + 8f + 46f, y + 11f, tp)
            y += barRow
        }
        // footer
        val fy = h - pad - 2f
        val sep = paint(Color.parseColor("#1C2944"), 1f, false, Paint.Style.STROKE)
        c.drawLine(pad, fy - 14f, w - pad, fy - 14f, sep)
        val lab = paint(MUTED, 11f)
        val valp = paint(SOFT, 11f, true)
        val l1 = j.optString("l_today"); val v1 = String.format(java.util.Locale.US, "%.2f kWh", j.optDouble("kwh", 0.0))
        val l2 = j.optString("l_cost"); val v2 = String.format(java.util.Locale.US, "%.2f EGP", j.optDouble("cost", 0.0))
        val l3 = j.optString("l_run"); val v3 = j.optString("on")
        d.pair(pad, fy, l1, v1, lab, valp)
        val w2 = d.pairWidth(l2, v2, lab, valp)
        d.pair((w - w2) / 2f, fy, l2, v2, lab, valp)
        val w3 = d.pairWidth(l3, v3, lab, valp)
        d.pair(w - pad - w3, fy, l3, v3, lab, valp)
    }

    // ---------------- strip widget 4x2: the app's strip card (header + 4 sockets + master; outlet 4 next to master) ----------------

    fun stripFor(ctx: Context, id: Int, j: JSONObject): JSONObject? {
        val arr = j.optJSONArray("strips") ?: return null
        if (arr.length() == 0) return null
        val mac = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("wstrip_" + id, "") ?: ""
        for (i in 0 until arr.length()) if (arr.getJSONObject(i).optString("mac") == mac) return arr.getJSONObject(i)
        return arr.getJSONObject(0)
    }

    // vertical bands of the strip widget; the click overlay (widget_strip_layout.xml) uses the same weights 28/44/28
    const val BAND_HEAD = 0.28f
    const val BAND_SOCK = 0.44f

    /** column (0 = leftmost) -> item: 0..3 = outlets 1..4, 4 = master. Outlet 4 always sits next to the master. */
    fun itemAt(col: Int, rtl: Boolean): Int = if (rtl) 4 - col else col

    private var iconFont: Typeface? = null
    private fun icons(ctx: Context): Typeface? {
        if (iconFont == null) {
            iconFont = try { Typeface.createFromAsset(ctx.assets, "flutter_assets/fonts/MaterialIcons-Regular.otf") } catch (e: Exception) { null }
        }
        return iconFont
    }

    private fun glyph(c: Canvas, ctx: Context, code: Int, cx: Float, cy: Float, size: Float, color: Int) {
        val tf = icons(ctx)
        val p = paint(color, size)
        if (tf == null) { c.drawCircle(cx, cy, size * 0.25f, p); return }
        p.typeface = tf
        p.textAlign = Paint.Align.CENTER
        val fm = p.fontMetrics
        c.drawText(String(Character.toChars(code)), cx, cy - (fm.ascent + fm.descent) / 2f, p)
    }

    private fun alpha(color: Int, a: Float): Int = Color.argb((a * 255).toInt().coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))

    private fun lerp(a: Int, b: Int, t: Float): Int = Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt())

    /** The app's _SocketPainter, scaled from its 64 px design to [d]. */
    private fun socket(c: Canvas, ctx: Context, cx: Float, cy: Float, d: Float, on: Boolean, load: Float, ring: Int, halo: Int,
                       master: Boolean, mixed: Boolean, pwr: Int) {
        val k = d / 64f
        val r = d / 2f
        val surface = Color.parseColor("#0E1628")
        val surface2 = Color.parseColor("#16213A")
        val track = paint(Color.parseColor("#1F2D48"), 1f, false, Paint.Style.STROKE)
        track.strokeWidth = 4f * k
        c.drawCircle(cx, cy, r - 3f * k, track)
        if (on) {
            val col = if (master) halo else ring
            val glowA = if (master) 0.08f + 0.22f * load else 0.22f
            val g = paint(Color.BLACK)
            val gr = (r - 6f * k) * 1.35f
            g.shader = RadialGradient(cx, cy, gr, intArrayOf(alpha(col, glowA), alpha(col, glowA), alpha(col, 0f)), floatArrayOf(0f, 0.6f, 1f), Shader.TileMode.CLAMP)
            c.drawCircle(cx, cy, gr, g)
            val frac = maxOf(if (master) 0.04f else 0.12f, load)
            val arc = paint(col, 1f, false, Paint.Style.STROKE)
            arc.strokeWidth = 4f * k
            arc.strokeCap = Paint.Cap.ROUND
            val sg = android.graphics.SweepGradient(cx, cy, intArrayOf(lerp(col, surface, 0.35f), col), floatArrayOf(0f, minOf(1f, frac)))
            val m = android.graphics.Matrix()
            m.setRotate(-90f, cx, cy)
            sg.setLocalMatrix(m)
            arc.shader = sg
            val rr = r - 3f * k
            c.drawArc(RectF(cx - rr, cy - rr, cx + rr, cy + rr), -90f, 360f * frac, false, arc)
        }
        val face = r - 9f * k
        val inner = on && !mixed
        val fp = paint(Color.BLACK)
        fp.shader = if (inner) {
            if (master) RadialGradient(cx, cy, face, alpha(ring, 0.16f), surface2, Shader.TileMode.CLAMP)
            else RadialGradient(cx, cy, face, alpha(ring, 0.35f), Color.parseColor("#0D2524"), Shader.TileMode.CLAMP)
        } else RadialGradient(cx, cy, face, surface2, Color.parseColor("#111B2F"), Shader.TileMode.CLAMP)
        c.drawCircle(cx, cy, face, fp)
        val edge = paint(if (inner) alpha(ring, 0.6f) else Color.parseColor("#1F2D48"), 1f, false, Paint.Style.STROKE)
        edge.strokeWidth = 1f * k
        c.drawCircle(cx, cy, face, edge)
        val rim = paint(Color.BLACK)
        rim.shader = RadialGradient(cx, cy, face, intArrayOf(Color.argb(0, 0, 0, 0), Color.argb(0, 0, 0, 0), Color.argb(97, 0, 0, 0)), floatArrayOf(0f, 0.68f, 1f), Shader.TileMode.CLAMP)
        c.drawCircle(cx, cy, face, rim)
        val hole = if (inner) lerp(ring, Color.BLACK, 0.6f) else Color.parseColor("#05080E")
        if (master) {
            val ic = if (inner) ring else if (mixed) ACCENT else hole
            glyph(c, ctx, pwr, cx, cy, face * 0.9f * 1.35f, ic)
        } else {
            c.save()
            c.rotate(45f, cx, cy)
            val hp = paint(hole)
            c.drawCircle(cx - face * 0.38f, cy, face * 0.13f, hp)
            c.drawCircle(cx + face * 0.38f, cy, face * 0.13f, hp)
            val clip = paint(if (inner) alpha(ring, 0.8f) else FAINT, 1f, false, Paint.Style.STROKE)
            clip.strokeWidth = 2f * k
            clip.strokeCap = Paint.Cap.ROUND
            c.drawLine(cx - face * 0.12f, cy - face * 0.82f, cx + face * 0.12f, cy - face * 0.82f, clip)
            c.drawLine(cx - face * 0.12f, cy + face * 0.82f, cx + face * 0.12f, cy + face * 0.82f, clip)
            c.restore()
        }
    }

    private fun wifiArcs(c: Canvas, x: Float, y: Float, size: Float, lvl: Int, color: Int) {
        // the app's WifiArcs: dot + 3 arcs, lit up to the signal level
        val cx = x + size / 2f
        val cy = y + size * 0.88f
        val sw = size * 0.13f
        if (lvl < 0) {
            val p = paint(FAINT, 1f, false, Paint.Style.STROKE); p.strokeWidth = sw
            c.drawLine(x + size * 0.2f, y + size * 0.2f, x + size * 0.8f, y + size * 0.8f, p)
            return
        }
        c.drawCircle(cx, cy, size * 0.1f, paint(color))
        val maxR = (size / 2f - sw / 2f) / Math.sin(50 * Math.PI / 180).toFloat()
        val radii = floatArrayOf(maxR * 0.36f, maxR * 0.68f, maxR)
        for (i in 0 until 3) {
            val p = paint(if (i + 1 <= lvl) color else alpha(color, 0.25f), 1f, false, Paint.Style.STROKE)
            p.strokeWidth = sw
            p.strokeCap = Paint.Cap.ROUND
            val rr = radii[i]
            c.drawArc(RectF(cx - rr, cy - rr, cx + rr, cy + rr), -140f, 100f, false, p)
        }
    }

    private fun ellipsize(s: String, p: Paint, max: Float): String {
        if (p.measureText(s) <= max) return s
        var e = s
        while (e.isNotEmpty() && p.measureText(e + "…") > max) e = e.substring(0, e.length - 1)
        return e + "…"
    }

    fun drawStrip(c: Canvas, ctx: Context, w: Float, h: Float, j: JSONObject, s: JSONObject?) {
        val rtl = j.optBoolean("ar", true)
        val d = Dr(c, w, h, rtl)
        val card = RectF(0.5f, 0.5f, w - 0.5f, h - 0.5f)
        c.drawRoundRect(card, 24f, 24f, paint(Color.parseColor("#0E1628")))
        if (s == null) {
            c.drawRoundRect(card, 24f, 24f, paint(BORDER, 1f, false, Paint.Style.STROKE))
            val p = paint(MUTED, 12f)
            p.textAlign = Paint.Align.CENTER
            c.drawText(j.optString("l_none", "Fisha"), w / 2, h / 2, p)
            return
        }
        val online = s.optBoolean("on", true)
        val tone = col(s.optString("tone"), BORDER)
        c.drawRoundRect(card, 24f, 24f, paint(alpha(tone, s.optDouble("toneA", 1.0).toFloat()), 1f, false, Paint.Style.STROKE))
        // header: dot, name, Wi-Fi arcs / "3 of 4 · 38°C · 221 V" / watts + amps at the end
        val pad = 12f
        val hh = h * BAND_HEAD
        val l1 = hh * 0.48f
        val l2 = hh * 0.88f
        c.drawCircle(d.xs(pad + 3f), l1 - 4f, 3.2f, paint(if (online) Color.parseColor("#3DDC97") else FAINT))
        val wp = paint(col(s.optString("wc"), TEXT), 16f, true)
        val wTxt = fmt(s.optInt("w"))
        val wUnit = paint(MUTED, 10f)
        val endW = wp.measureText(wTxt) + 3f + wUnit.measureText("W")
        d.textE("W", pad, l1, wUnit)
        d.textE(wTxt, pad + wUnit.measureText("W") + 3f, l1, wp)
        val amps = s.optString("amps")
        if (amps.isNotEmpty()) d.textE(amps, pad, l2, paint(SOFT, 10f, true))
        val np = paint(TEXT, 13.5f, true)
        val nameMax = w - 2 * pad - 12f - endW - 26f
        val name = ellipsize(s.optString("name"), np, nameMax)
        d.textS(name, pad + 11f, l1, np)
        val nw = np.measureText(name)
        val wifiX = if (rtl) w - (pad + 11f + nw + 6f) - 13f else pad + 11f + nw + 6f
        wifiArcs(c, wifiX, l1 - 12f, 13f, s.optInt("wifi", -1), col(s.optString("wifiC"), FAINT))
        // second line, each part in its own color
        var x = pad + 11f
        fun part(t: String, color: Int, bold: Boolean) {
            if (t.isEmpty()) return
            val p = paint(color, 10.5f, bold)
            d.textS(t, x, l2, p)
            x += p.measureText(t) + 5f
        }
        part(s.optString("sub"), col(s.optString("subC"), SOFT), false)
        if (online) {
            part("·", BORDER, false)
            part(s.optInt("t").toString() + "°C", col(s.optString("tc"), SOFT), true)
            if (s.optString("v").isNotEmpty()) {
                part("·", BORDER, false)
                part(s.optString("v"), col(s.optString("vc"), SOFT), true)
            }
        }
        // the strip body (well)
        val well = RectF(5f, hh + 1f, w - 5f, h - 5f)
        val wellP = paint(Color.BLACK)
        wellP.shader = LinearGradient(0f, well.top, 0f, well.bottom, Color.parseColor("#16213A"), Color.parseColor("#0E1628"), Shader.TileMode.CLAMP)
        c.drawRoundRect(well, 20f, 20f, wellP)
        c.drawRoundRect(well, 20f, 20f, paint(Color.parseColor("#1F2D48"), 1f, false, Paint.Style.STROKE))
        val outs = s.optJSONArray("outs")
        val m = s.optJSONObject("m")
        val colW = w / 5f
        val sockTop = hh
        val sockH = h * BAND_SOCK
        val labTop = sockTop + sockH
        val labH = h - labTop
        val dia = minOf(colW * 0.80f, sockH - 12f)
        for (ci in 0 until 5) {
            val item = itemAt(ci, rtl)
            val cx = colW * (ci + 0.5f)
            val cy = sockTop + 11f + (sockH - 11f) / 2f
            val o: JSONObject? = if (item < 4) (if (outs != null && item < outs.length()) outs.getJSONObject(item) else null) else m
            if (o == null) continue
            val isMaster = item == 4
            // badges above the socket
            val b = o.optJSONArray("b")
            if (b != null && b.length() > 0) {
                val n = minOf(b.length(), 4)
                val bs = 9.5f
                var bx = cx - (n - 1) * (bs + 1f) / 2f
                for (i in 0 until n) {
                    val e = b.getJSONArray(i)
                    glyph(c, ctx, e.optInt(0), bx, sockTop + 6.5f, bs, col(e.optString(1), MUTED))
                    bx += bs + 1f
                }
            }
            if (isMaster) {
                socket(c, ctx, cx, cy, dia, o.optBoolean("on"), o.optDouble("load", 0.0).toFloat(), col(o.optString("rc"), ACCENT),
                    col(o.optString("halo"), ACCENT), true, o.optBoolean("mixed"), s.optInt("pwr", 0xe8ac))
            } else {
                socket(c, ctx, cx, cy, dia, o.optBoolean("on"), o.optDouble("load", 0.0).toFloat(), col(o.optString("rc"), ACCENT),
                    ACCENT, false, false, 0)
            }
            // labels: name, then watts and temperature
            val on = o.optBoolean("on")
            val lp = paint(if (isMaster || on) TEXT else SOFT, 10f, true)
            lp.textAlign = Paint.Align.CENTER
            val label = if (isMaster) o.optString("lbl") else o.optString("name")
            c.drawText(ellipsize(label, lp, colW - 6f), cx, labTop + labH * 0.36f, lp)
            val vy = labTop + labH * 0.74f
            if (isMaster) {
                val vp = paint(col(s.optString("wc"), MUTED), 9.5f, true)
                vp.textAlign = Paint.Align.CENTER
                c.drawText(if (online) fmt(s.optInt("w")) + " W" else "—", cx, vy, vp)
            } else if (!online) {
                val vp = paint(FAINT, 9.5f)
                vp.textAlign = Paint.Align.CENTER
                c.drawText("—", cx, vy, vp)
            } else {
                val ww = o.optDouble("w", 0.0)
                val wTx = if (on) (if (ww < 10) String.format(java.util.Locale.US, "%.1f W", ww) else fmt(ww.toInt()) + " W") else ""
                val tTx = o.optInt("t").toString() + "°"
                val vp = paint(col(o.optString("wc"), MUTED), 9.5f, true)
                val tp = paint(col(o.optString("tc"), MUTED), 9.5f, true)
                val gap = if (wTx.isEmpty()) 0f else 4f
                val tot = vp.measureText(wTx) + gap + tp.measureText(tTx)
                vp.textAlign = Paint.Align.LEFT
                tp.textAlign = Paint.Align.LEFT
                val x0 = cx - tot / 2f
                c.drawText(wTx, x0, vy, vp)
                c.drawText(tTx, x0 + vp.measureText(wTx) + gap, vy, tp)
            }
        }
        if (!online) c.drawRoundRect(card, 24f, 24f, paint(Color.argb(102, 7, 13, 25)))
    }

    // ---------------- toggling an outlet from the widget (home network only) ----------------

    private fun toast(ctx: Context, msg: String) {
        if (msg.isEmpty()) return
        Handler(Looper.getMainLooper()).post { Toast.makeText(ctx.applicationContext, msg, Toast.LENGTH_SHORT).show() }
    }

    private fun send(url: String, hdr: JSONObject?, mac: String, n: Int, on: Boolean): Boolean {
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 3000
            conn.readTimeout = 6000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            if (hdr != null) {
                val keys = hdr.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    conn.setRequestProperty(k, hdr.optString(k))
                }
            }
            val body = JSONObject().put("mac", mac).put("outlet", n).put("on", on).toString()
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val txt = stream?.bufferedReader()?.readText() ?: ""
            conn.disconnect()
            JSONObject(txt).optBoolean("ok", false)
        } catch (e: Exception) {
            false
        }
    }

    /** n = 1..4 one outlet, 0 = the master (all on / all off, skipping what the app would ask about). */
    fun toggle(ctx: Context, id: Int, n: Int) {
        val j = data(ctx)
        val s = stripFor(ctx, id, j) ?: return
        if (!s.optBoolean("on", true)) return
        val outs = s.optJSONArray("outs") ?: return
        val url = j.optString("url")
        val hdr = j.optJSONObject("hdr")
        val mac = s.optString("mac")
        if (n == 0) {
            val m = s.optJSONObject("m")
            if (m == null || m.optBoolean("lock")) { toast(ctx, j.optString("t_lock")); return }
            if (url.isEmpty()) { toast(ctx, j.optString("t_away")); return }
            var anyOn = false
            for (i in 0 until outs.length()) if (outs.getJSONObject(i).optBoolean("on")) anyOn = true
            val want = !anyOn
            var skipped = false
            var failed = false
            for (i in 0 until outs.length()) {
                val o = outs.getJSONObject(i)
                if (o.optBoolean("on") == want) continue
                if (o.optBoolean(if (want) "lockOn" else "lockOff")) { skipped = true; continue }
                if (send(url, hdr, mac, o.optInt("n"), want)) o.put("on", want) else failed = true
            }
            saveData(ctx, j)
            updateAll(ctx)
            if (failed) toast(ctx, j.optString("t_fail")) else if (skipped) toast(ctx, j.optString("t_lock"))
            return
        }
        var o: JSONObject? = null
        for (i in 0 until outs.length()) if (outs.getJSONObject(i).optInt("n") == n) o = outs.getJSONObject(i)
        if (o == null) return
        val want = !o.optBoolean("on")
        if (o.optBoolean(if (want) "lockOn" else "lockOff")) { toast(ctx, j.optString("t_lock")); return }
        if (url.isEmpty()) { toast(ctx, j.optString("t_away")); return }
        if (send(url, hdr, mac, n, want)) {
            o.put("on", want)
            saveData(ctx, j)
            updateAll(ctx)
        } else {
            toast(ctx, j.optString("t_fail"))
        }
    }

    /** Opens the app on a strip (n = -1) or an outlet's sheet: the same options as a long press in the app. */
    fun openSheet(ctx: Context, reqCode: Int, mac: String, n: Int): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java)
        intent.putExtra("w_open", mac + "|" + n)
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(ctx, reqCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}

class FishaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle?) {
        render(context, appWidgetManager, appWidgetId)
    }

    private fun render(ctx: Context, mgr: AppWidgetManager, id: Int) {
        val size = FishaWidgets.sizeDp(mgr, id, 250f, 190f)
        val j = FishaWidgets.data(ctx)
        val bmp = FishaWidgets.bitmap(ctx, size.first, size.second) { c, w, h -> FishaWidgets.drawMain(c, w, h, j) }
        val views = RemoteViews(ctx.packageName, R.layout.widget_layout)
        views.setImageViewBitmap(R.id.widget_img, bmp)
        views.setOnClickPendingIntent(R.id.widget_container, FishaWidgets.openApp(ctx, id))
        mgr.updateAppWidget(id, views)
    }
}

class FishaStripWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle?) {
        render(context, appWidgetManager, appWidgetId)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val e = context.getSharedPreferences(FishaWidgets.PREFS, Context.MODE_PRIVATE).edit()
        for (id in appWidgetIds) e.remove("wstrip_" + id)
        e.apply()
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == FishaWidgets.ACTION_TOGGLE) {
            val id = intent.getIntExtra("id", 0)
            val n = intent.getIntExtra("n", 0)
            val pending = goAsync()
            Thread {
                try {
                    FishaWidgets.toggle(context, id, n)
                } catch (e: Exception) {
                } finally {
                    pending.finish()
                }
            }.start()
            return
        }
        super.onReceive(context, intent)
    }

    private fun render(ctx: Context, mgr: AppWidgetManager, id: Int) {
        val size = FishaWidgets.sizeDp(mgr, id, 300f, 140f)
        val j = FishaWidgets.data(ctx)
        val s = FishaWidgets.stripFor(ctx, id, j)
        val rtl = j.optBoolean("ar", true)
        val bmp = FishaWidgets.bitmap(ctx, size.first, size.second) { c, w, h -> FishaWidgets.drawStrip(c, ctx, w, h, j, s) }
        val views = RemoteViews(ctx.packageName, R.layout.widget_strip_layout)
        views.setImageViewBitmap(R.id.strip_img, bmp)
        val mac = s?.optString("mac") ?: ""
        views.setOnClickPendingIntent(R.id.strip_hd, if (mac.isEmpty()) FishaWidgets.openApp(ctx, id) else FishaWidgets.openSheet(ctx, id * 100 + 50, mac, -1))
        val sockIds = intArrayOf(R.id.sock_0, R.id.sock_1, R.id.sock_2, R.id.sock_3, R.id.sock_4)
        val labIds = intArrayOf(R.id.lab_0, R.id.lab_1, R.id.lab_2, R.id.lab_3, R.id.lab_4)
        for (col in 0 until 5) {
            val item = FishaWidgets.itemAt(col, rtl)
            val n = if (item == 4) 0 else item + 1
            val i = Intent(ctx, FishaStripWidgetProvider::class.java)
            i.action = FishaWidgets.ACTION_TOGGLE
            i.putExtra("id", id)
            i.putExtra("n", n)
            val pi = PendingIntent.getBroadcast(ctx, id * 100 + n, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(sockIds[col], pi)
            val open = if (mac.isEmpty()) FishaWidgets.openApp(ctx, id) else FishaWidgets.openSheet(ctx, id * 100 + 10 + n, mac, if (n == 0) -1 else n)
            views.setOnClickPendingIntent(labIds[col], open)
        }
        mgr.updateAppWidget(id, views)
    }
}

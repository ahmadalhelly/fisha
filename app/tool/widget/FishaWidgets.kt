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

    // ---------------- strip widget "شكل المشترك": four sockets that light up ----------------

    fun stripFor(ctx: Context, id: Int, j: JSONObject): JSONObject? {
        val arr = j.optJSONArray("strips") ?: return null
        if (arr.length() == 0) return null
        val mac = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("wstrip_" + id, "") ?: ""
        for (i in 0 until arr.length()) if (arr.getJSONObject(i).optString("mac") == mac) return arr.getJSONObject(i)
        return arr.getJSONObject(0)
    }

    fun drawStrip(c: Canvas, w: Float, h: Float, j: JSONObject, s: JSONObject?) {
        val rtl = j.optBoolean("ar", true)
        val d = Dr(c, w, h, rtl)
        val bg = paint(Color.BLACK)
        bg.shader = RadialGradient(w / 2, 0f, maxOf(w, h) * 1.1f, Color.parseColor("#15233F"), Color.parseColor("#0B1324"), Shader.TileMode.CLAMP)
        c.drawRoundRect(RectF(0f, 0f, w, h), 26f, 26f, bg)
        c.drawRoundRect(RectF(0.5f, 0.5f, w - 0.5f, h - 0.5f), 26f, 26f, paint(BORDER, 1f, false, Paint.Style.STROKE))
        if (s == null) {
            val p = paint(MUTED, 12f)
            p.textAlign = Paint.Align.CENTER
            c.drawText(j.optString("l_none", "Fisha"), w / 2, h / 2, p)
            return
        }
        val online = s.optBoolean("on", true)
        val pad = 13f
        val hh = h * 0.20f
        val rh = h * 0.29f
        d.textS(s.optString("name"), pad, hh * 0.66f, paint(SOFT, 12.5f))
        val t = s.optInt("t")
        if (online) d.textE(t.toString() + "°C", pad, hh * 0.66f, paint(tempColor(t), 11.5f, true))
        val outs = s.optJSONArray("outlets") ?: s.optJSONArray("o")
        val cellW = (w - 2 * pad) / 2f
        for (k in 0 until 4) {
            val row = k / 2
            val colI = k % 2
            val cx = d.xs(pad + cellW * (colI + 0.5f))
            val cy = hh + rh * (row + 0.5f)
            val r = (minOf(cellW, rh) / 2f) - 4f
            val o = if (outs != null && k < outs.length()) outs.getJSONObject(k) else null
            val on = online && o != null && o.optBoolean("on")
            val oc = col(o?.optString("c"), ACCENT)
            if (on) {
                val g = paint(Color.BLACK)
                g.shader = RadialGradient(cx, cy, r * 1.35f, Color.argb(80, Color.red(oc), Color.green(oc), Color.blue(oc)), Color.argb(0, Color.red(oc), Color.green(oc), Color.blue(oc)), Shader.TileMode.CLAMP)
                c.drawCircle(cx, cy, r * 1.35f, g)
            }
            c.drawCircle(cx, cy, r, paint(Color.parseColor("#101A2E")))
            val ring = paint(if (on) oc else Color.parseColor("#23314E"), 1f, false, Paint.Style.STROKE)
            ring.strokeWidth = if (on) 1.8f else 1f
            c.drawCircle(cx, cy, r, ring)
            val hole = paint(if (on) oc else Color.parseColor("#070D19"))
            c.drawCircle(cx - r * 0.34f, cy - r * 0.06f, r * 0.12f, hole)
            c.drawCircle(cx + r * 0.34f, cy - r * 0.06f, r * 0.12f, hole)
            if (on && o != null) {
                val wp = paint(SOFT, 9f)
                wp.textAlign = Paint.Align.CENTER
                c.drawText(fmt(o.optInt("w")) + " W", cx, cy + r * 0.72f, wp)
            }
        }
        val fy = hh + rh * 2f + (h - hh - rh * 2f) * 0.62f
        d.textS(j.optString("l_total"), pad, fy, paint(MUTED, 11.5f))
        d.textE(if (online) fmt(s.optInt("w")) + " W" else "—", pad, fy, paint(TEXT, 15f, true))
    }

    // ---------------- toggling an outlet from the widget (home network only) ----------------

    private fun toast(ctx: Context, msg: String) {
        if (msg.isEmpty()) return
        Handler(Looper.getMainLooper()).post { Toast.makeText(ctx.applicationContext, msg, Toast.LENGTH_SHORT).show() }
    }

    fun toggle(ctx: Context, id: Int, n: Int) {
        val j = data(ctx)
        val s = stripFor(ctx, id, j) ?: return
        val outs = s.optJSONArray("o") ?: return
        var o: JSONObject? = null
        for (i in 0 until outs.length()) if (outs.getJSONObject(i).optInt("n") == n) o = outs.getJSONObject(i)
        if (o == null) return
        if (o.optBoolean("lock")) { toast(ctx, j.optString("t_lock")); return }
        val url = j.optString("url")
        if (url.isEmpty()) { toast(ctx, j.optString("t_away")); return }
        val want = !o.optBoolean("on")
        var ok = false
        try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 3000
            conn.readTimeout = 6000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            val hdr = j.optJSONObject("hdr")
            if (hdr != null) {
                val keys = hdr.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    conn.setRequestProperty(k, hdr.optString(k))
                }
            }
            val body = JSONObject().put("mac", s.optString("mac")).put("outlet", n).put("on", want).toString()
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val txt = stream?.bufferedReader()?.readText() ?: ""
            ok = JSONObject(txt).optBoolean("ok", false)
            conn.disconnect()
        } catch (e: Exception) {
            ok = false
        }
        if (ok) {
            o.put("on", want)
            saveData(ctx, j)
            updateAll(ctx)
        } else {
            toast(ctx, j.optString("t_fail"))
        }
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
        val size = FishaWidgets.sizeDp(mgr, id, 150f, 150f)
        val j = FishaWidgets.data(ctx)
        val s = FishaWidgets.stripFor(ctx, id, j)
        val bmp = FishaWidgets.bitmap(ctx, size.first, size.second) { c, w, h -> FishaWidgets.drawStrip(c, w, h, j, s) }
        val views = RemoteViews(ctx.packageName, R.layout.widget_strip_layout)
        views.setImageViewBitmap(R.id.strip_img, bmp)
        val open = FishaWidgets.openApp(ctx, id)
        views.setOnClickPendingIntent(R.id.strip_hd, open)
        views.setOnClickPendingIntent(R.id.strip_ft, open)
        val ids = intArrayOf(R.id.sock_1, R.id.sock_2, R.id.sock_3, R.id.sock_4)
        for (k in 0 until 4) {
            val i = Intent(ctx, FishaStripWidgetProvider::class.java)
            i.action = FishaWidgets.ACTION_TOGGLE
            i.putExtra("id", id)
            i.putExtra("n", k + 1)
            val pi = PendingIntent.getBroadcast(ctx, id * 10 + k + 1, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(ids[k], pi)
        }
        mgr.updateAppWidget(id, views)
    }
}

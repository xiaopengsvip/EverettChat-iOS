package top.vios.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * RichMessageRenderer —— AI Native 消息渲染器
 * 支持：标题 / 段落 / 代码块(语言+复制+横滚) / 引用 / 列表 / 表格 / 分隔线 / 粗体 / 行内代码 / 链接
 * 设计：Document Style（无气泡感），留白排版，克制圆角。
 */

// ================= 块级 Markdown 解析 =================

sealed class MdBlock {
    data class Heading(val level: Int, val text: String) : MdBlock()
    data class Paragraph(val text: String) : MdBlock()
    data class Code(val lang: String, val code: String) : MdBlock()
    data class Quote(val text: String) : MdBlock()
    data class UnorderedItem(val text: String) : MdBlock()
    data class OrderedItem(val index: Int, val text: String) : MdBlock()
    data class Table(val header: List<String>, val rows: List<List<String>>) : MdBlock()
    object Divider : MdBlock()
}

fun parseMarkdown(src: String): List<MdBlock> {
    val blocks = mutableListOf<MdBlock>()
    val lines = src.replace("\r\n", "\n").split("\n")
    var i = 0
    val orderedRe = Regex("^\\d+\\.")
    while (i < lines.size) {
        val t = lines[i].trim()
        when {
            // 代码块 ```lang ... ```
            t.startsWith("```") -> {
                val lang = t.removePrefix("```").trim()
                val code = StringBuilder()
                i++
                while (i < lines.size && !lines[i].trim().startsWith("```")) {
                    code.append(lines[i]).append("\n")
                    i++
                }
                i++ // 跳过闭合 ```
                blocks.add(MdBlock.Code(lang, code.toString().trimEnd()))
            }
            // 标题
            t.startsWith("#") && t.length > 1 -> {
                val level = t.takeWhile { it == '#' }.length
                blocks.add(MdBlock.Heading(level, t.drop(level).trim()))
                i++
            }
            // 引用
            t.startsWith(">") -> { blocks.add(MdBlock.Quote(t.drop(1).trim())); i++ }
            // 无序列表
            (t.startsWith("- ") || t.startsWith("* ") || t.startsWith("• ")) -> {
                blocks.add(MdBlock.UnorderedItem(t.drop(2).trim())); i++
            }
            // 有序列表
            orderedRe.containsMatchIn(t) -> {
                val num = t.substringBefore(".").toIntOrNull() ?: 1
                val body = t.replace(orderedRe, "").trim()
                blocks.add(MdBlock.OrderedItem(num, body)); i++
            }
            // 表格 | a | b |
            t.startsWith("|") && t.endsWith("|") && t.count { it == '|' } >= 3 -> {
                val header = t.split("|").filter { it.isNotBlank() }.map { it.trim() }
                i++
                val rows = mutableListOf<List<String>>()
                // 跳过分隔行 |---|
                if (i < lines.size && lines[i].trim().matches(Regex("^\\|?[\\s:|-]+\\|?$")) && lines[i].trim().contains("-")) i++
                while (i < lines.size) {
                    val rt = lines[i].trim()
                    if (!rt.startsWith("|") || !rt.endsWith("|") || rt.count { it == '|' } < 3) break
                    rows.add(rt.split("|").filter { it.isNotBlank() }.map { it.trim() })
                    i++
                }
                blocks.add(MdBlock.Table(header, rows))
            }
            // 分隔线
            t.matches(Regex("^[-*_]{3,}$")) -> { blocks.add(MdBlock.Divider); i++ }
            // 空行
            t.isEmpty() -> i++
            // 段落（合并到空行/块边界）
            else -> {
                val para = StringBuilder(t)
                i++
                while (i < lines.size) {
                    val nt = lines[i].trim()
                    if (nt.isEmpty()) break
                    if (nt.startsWith("#") || nt.startsWith("```") || nt.startsWith(">") ||
                        nt.startsWith("- ") || nt.startsWith("* ") || nt.startsWith("• ") ||
                        orderedRe.containsMatchIn(nt) || nt.matches(Regex("^[-*_]{3,}$")) ||
                        (nt.startsWith("|") && nt.endsWith("|") && nt.count { it == '|' } >= 3)) break
                    para.append("\n").append(nt)
                    i++
                }
                blocks.add(MdBlock.Paragraph(para.toString()))
            }
        }
    }
    return blocks
}

// ================= 行内样式（粗体 / 行内代码 / 链接） =================

private val BOLD_RE = Regex("\\*\\*(.+?)\\*\\*")
private val CODE_RE = Regex("`([^`]+)`")
private val LINK_RE = Regex("\\[([^\\]]+)\\]\\(([^)]+)\\)")

private fun buildInline(text: String, baseColor: Color, codeBg: Color, codeColor: Color): AnnotatedString {
    return buildAnnotatedString {
        var pos = 0
        // 按位置合并匹配
        data class M(val start: Int, val end: Int, val kind: Int, val a: String, val b: String)
        val ms = mutableListOf<M>()
        BOLD_RE.findAll(text).forEach { ms.add(M(it.range.first, it.range.last + 1, 1, it.groupValues[1], "")) }
        CODE_RE.findAll(text).forEach { ms.add(M(it.range.first, it.range.last + 1, 2, it.groupValues[1], "")) }
        LINK_RE.findAll(text).forEach { ms.add(M(it.range.first, it.range.last + 1, 3, it.groupValues[1], it.groupValues[2])) }
        ms.sortBy { it.start }
        for (m in ms) {
            if (m.start < pos) continue
            append(text.substring(pos, m.start))
            when (m.kind) {
                1 -> withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = baseColor)) { append(m.a) }
                2 -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = codeBg, color = codeColor)) { append(m.a) }
                3 -> withStyle(SpanStyle(color = AppColors.info, textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline)) { append(m.a) }
            }
            pos = m.end
        }
        if (pos < text.length) append(text.substring(pos))
    }
}

// ================= 视图组件 =================

@Composable
fun RichMessageContent(
    text: String,
    baseColor: Color,
    modifier: Modifier = Modifier,
    maxWidth: androidx.compose.ui.unit.Dp = 320.dp
) {
    val blocks = remember(text) { parseMarkdown(text) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        // key(index) 局部重组：流式更新时只有变化的块重绘，避免整页重组
        blocks.forEachIndexed { index, block ->
            androidx.compose.runtime.key(index) {
                when (block) {
                    is MdBlock.Heading -> Text(
                        block.text,
                        color = baseColor,
                        fontSize = when (block.level) { 1 -> 19.sp; 2 -> 16.sp; else -> 14.sp },
                        fontWeight = FontWeight.Bold
                    )
                    is MdBlock.Paragraph -> Text(
                        buildInline(block.text, baseColor, AppColors.surfaceHigh, AppColors.info),
                        color = baseColor, fontSize = 15.sp, lineHeight = 21.sp
                    )
                    is MdBlock.Code -> CodeBlockView(block, maxWidth)
                    is MdBlock.Quote -> QuoteView(block.text, baseColor)
                    is MdBlock.UnorderedItem -> ListRow("•", block.text, baseColor)
                    is MdBlock.OrderedItem -> ListRow("${block.index}.", block.text, baseColor)
                    is MdBlock.Table -> TableView(block, maxWidth)
                    MdBlock.Divider -> Box(Modifier.fillMaxWidth().height(1.dp).background(AppColors.outline))
                }
            }
        }
    }
}

@Composable
private fun CodeBlockView(block: MdBlock.Code, maxWidth: androidx.compose.ui.unit.Dp) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(AppColors.surfaceHigh.copy(alpha = 0.7f), RoundedCornerShape(AppRadius.small))
            .padding(vertical = 8.dp)
    ) {
        if (block.lang.isNotEmpty() || true) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    block.lang.ifEmpty { "code" },
                    color = AppColors.textTertiary,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.weight(1f)
                )
                // 复制按钮
                val ctx = androidx.compose.ui.platform.LocalContext.current
                Text(
                    "复制",
                    color = AppColors.primary,
                    fontSize = 11.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable {
                            val cm = ctx.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                            cm.setPrimaryClip(android.content.ClipData.newPlainText("code", block.code))
                            android.widget.Toast.makeText(ctx, "已复制", android.widget.Toast.LENGTH_SHORT).show()
                        }
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }
        Text(
            block.code,
            color = AppColors.textPrimary.copy(alpha = 0.9f),
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace,
            lineHeight = 17.sp,
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 12.dp)
        )
    }
}

@Composable
private fun QuoteView(text: String, baseColor: Color) {
    Row(Modifier.fillMaxWidth()) {
        Box(
            Modifier
                .width(3.dp)
                .height(IntrinsicSize.Min)
                .background(AppColors.primary.copy(alpha = 0.5f), RoundedCornerShape(2.dp))
        )
        Spacer(Modifier.width(8.dp))
        Text(
            buildInline(text, baseColor.copy(alpha = 0.75f), AppColors.surfaceHigh, AppColors.info),
            color = baseColor.copy(alpha = 0.75f),
            fontSize = 13.sp,
            lineHeight = 19.sp,
            modifier = Modifier.padding(vertical = 2.dp)
        )
    }
}

@Composable
private fun ListRow(marker: String, text: String, baseColor: Color) {
    Row(Modifier.fillMaxWidth()) {
        Text(marker, color = AppColors.primary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(18.dp))
        Text(
            buildInline(text, baseColor, AppColors.surfaceHigh, AppColors.info),
            color = baseColor, fontSize = 14.sp, lineHeight = 20.sp,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun TableView(block: MdBlock.Table, maxWidth: androidx.compose.ui.unit.Dp) {
    val scroll = rememberScrollState()
    Column(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(scroll)
            .background(AppColors.surfaceHigh.copy(alpha = 0.6f), RoundedCornerShape(AppRadius.small))
    ) {
        // 表头
        Row(Modifier.background(AppColors.surfaceAlt)) {
            block.header.forEach { h ->
                Text(
                    h, color = AppColors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp).width(96.dp)
                )
            }
        }
        // 分隔线
        Box(Modifier.fillMaxWidth().height(1.dp).background(AppColors.outlineStrong))
        // 数据行
        block.rows.forEachIndexed { idx, row ->
            Row(Modifier.background(if (idx % 2 == 0) Color.Transparent else AppColors.surfaceAlt.copy(alpha = 0.4f))) {
                row.forEach { cell ->
                    Text(
                        cell, color = AppColors.textSecondary, fontSize = 12.sp,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp).width(96.dp)
                    )
                }
            }
        }
    }
}

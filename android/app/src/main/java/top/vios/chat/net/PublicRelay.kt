package top.vios.chat.net

/**
 * 公网中继服务器配置
 * 部署在 Cloudflare Workers + Durable Objects
 * 全球节点，国内通过 relay.vios.top 可访问
 */
object PublicRelay {
    const val WS_URL = "wss://relay.vios.top/ws"
    const val HTTP_URL = "https://relay.vios.top"
    const val ROOM = "everett-public"
    const val PASSPHRASE = "everett-public"
    const val NODE_NAME = "云中继(CF)"
}
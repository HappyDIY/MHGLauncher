import { defineConfig } from "vitepress";

const repository = "https://github.com/HappyDIY/MHGLauncher";

export default defineConfig({
  lang: "zh-CN",
  title: "MHGLauncher",
  titleTemplate: ":title | MHGLauncher 官方文档",
  description: "MHGLauncher 的用户手册、开发者指南与云服务运维文档。",
  base: "/",
  lastUpdated: true,
  head: [
    ["link", { rel: "icon", type: "image/png", href: "/logo-64.png" }],
    ["meta", { name: "theme-color", content: "#087e8b" }],
    ["meta", { name: "color-scheme", content: "light dark" }]
  ],
  themeConfig: {
    logo: "/logo-96.png",
    siteTitle: "MHGLauncher 文档",
    nav: [
      { text: "用户手册", link: "/guide/getting-started" },
      { text: "开发指南", link: "/development/architecture" },
      { text: "部署运维", link: "/operations/self-hosting" },
      { text: "常见问题", link: "/reference/faq" }
    ],
    sidebar: {
      "/guide/": [
        {
          text: "开始使用",
          items: [
            { text: "构建与运行", link: "/guide/getting-started" },
            { text: "首次启动与账号", link: "/guide/first-launch" }
          ]
        },
        {
          text: "使用指南",
          items: [
            { text: "游戏管理", link: "/guide/game-management" },
            { text: "旅行数据", link: "/guide/player-data" },
            { text: "云同步", link: "/guide/cloud-sync" }
          ]
        },
        {
          text: "帮助与安全",
          items: [
            { text: "故障排查", link: "/guide/troubleshooting" },
            { text: "隐私与风险", link: "/guide/security" },
            { text: "常见问题", link: "/reference/faq" }
          ]
        }
      ],
      "/development/": [
        {
          text: "开发者指南",
          items: [
            { text: "系统架构", link: "/development/architecture" },
            { text: "本地开发", link: "/development/local-development" },
            { text: "API 边界", link: "/development/api-boundary" },
            { text: "测试与质量", link: "/development/testing" },
            { text: "运行时与打包", link: "/development/runtime-packaging" },
            { text: "参与贡献", link: "/development/contributing" }
          ]
        }
      ],
      "/operations/": [
        {
          text: "部署运维",
          items: [
            { text: "自托管云服务", link: "/operations/self-hosting" }
          ]
        }
      ],
      "/reference/": [
        {
          text: "参考",
          items: [
            { text: "常见问题", link: "/reference/faq" },
            { text: "隐私与风险", link: "/guide/security" }
          ]
        }
      ]
    },
    socialLinks: [
      { icon: "github", link: repository }
    ],
    search: {
      provider: "local",
      options: {
        locales: {
          root: {
            translations: {
              button: {
                buttonText: "搜索文档",
                buttonAriaLabel: "搜索文档"
              },
              modal: {
                noResultsText: "没有找到相关内容",
                resetButtonTitle: "清除查询",
                footer: {
                  selectText: "选择",
                  navigateText: "切换",
                  closeText: "关闭"
                }
              }
            }
          }
        }
      }
    },
    outline: {
      level: [2, 3],
      label: "本页内容"
    },
    docFooter: {
      prev: "上一页",
      next: "下一页"
    },
    lastUpdated: {
      text: "最近更新"
    },
    editLink: {
      pattern: `${repository}/edit/main/docs/:path`,
      text: "在 GitHub 上编辑此页"
    },
    footer: {
      message: "MHGLauncher 是非官方第三方项目，与米哈游及 HoYoverse 无隶属、授权或合作关系。",
      copyright: "文档内容随开发预览版本持续更新"
    },
    externalLinkIcon: true
  }
});

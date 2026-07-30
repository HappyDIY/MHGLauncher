---
layout: page
title: MHGLauncher 官方文档
titleTemplate: false
description: 在 Mac 上安装、运行和参与开发 MHGLauncher。
---

<main class="docs-home">
  <section class="home-masthead" aria-labelledby="home-title">
    <img class="home-logo" src="/logo-256.png" alt="MHGLauncher 应用图标">
    <p class="home-kicker">开发预览 · 简体中文</p>
    <h1 id="home-title"><span>MHGLauncher</span> <span>官方文档</span></h1>
    <p class="home-lead">
      从 Mac 上的游戏安装与旅行数据管理，到本地开发和云服务运维，
      这里集中记录 MHGLauncher 当前版本的使用方式与技术约定。
    </p>
    <nav class="home-actions" aria-label="快速入口">
      <a class="home-action primary" href="/guide/getting-started.html">开始使用</a>
      <a class="home-action" href="/development/architecture.html">了解架构</a>
    </nav>
  </section>

  <aside class="preview-notice" role="note" aria-label="开发预览提醒">
    <strong>使用前请留意：</strong>
    MHGLauncher 是仍在开发中的非官方第三方项目。通过兼容层运行游戏可能带来账号处罚、
    数据损坏或运行异常风险，请先阅读隐私与风险说明并备份重要文件。
  </aside>

  <section class="home-section" aria-labelledby="audience-title">
    <h2 id="audience-title">选择你的入口</h2>
    <p class="section-intro">文档按照实际任务组织，不需要先了解整个项目。</p>
    <div class="audience-grid">
      <article class="audience-card">
        <h3>普通用户</h3>
        <p>了解构建限制、首次登录、游戏安装更新、祈愿记录和云同步。</p>
        <a href="/guide/getting-started.html">打开用户手册 →</a>
      </article>
      <article class="audience-card">
        <h3>项目贡献者</h3>
        <p>熟悉四组件架构、Unix Socket API、fixture 测试与运行时打包。</p>
        <a href="/development/architecture.html">打开开发指南 →</a>
      </article>
      <article class="audience-card">
        <h3>服务运维者</h3>
        <p>使用 Docker Compose 部署可选云端与管理后台，并管理生产密钥。</p>
        <a href="/operations/self-hosting.html">打开部署文档 →</a>
      </article>
    </div>
  </section>

  <section class="home-section" aria-labelledby="facts-title">
    <h2 id="facts-title">当前支持范围</h2>
    <p class="section-intro">首版目标保持克制，未列出的平台和游戏不属于当前产品范围。</p>
    <div class="home-facts" role="list">
      <div class="home-fact" role="listitem"><strong>macOS 26+</strong><span>目标系统</span></div>
      <div class="home-fact" role="listitem"><strong>Apple 芯片</strong><span>arm64 架构</span></div>
      <div class="home-fact" role="listitem"><strong>国服</strong><span>《原神》服务器</span></div>
      <div class="home-fact" role="listitem"><strong>可选云端</strong><span>本地功能可独立使用</span></div>
    </div>
  </section>
</main>

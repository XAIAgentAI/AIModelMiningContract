# AI Model Mining Contract 项目文档

## 项目概述

AI Model Mining Contract 是一个基于DBC的去中心化应用（DApp），专门用于GPU挖矿奖励的NFT质押系统。该项目使用Scaffold-ETH 2框架构建，其中前端部分代码仅用于自测

## 技术栈

- **前端**: NextJS, TypeScript, RainbowKit, Wagmi, Viem
- **智能合约**: Solidity 0.8.26, Foundry, OpenZeppelin
- **开发工具**: Yarn, Husky, ESLint, Prettier
- **区块链**: 以太坊及兼容网络

## 项目结构

```
AIModelMiningContract/
├── LICENSE                     # 项目许可证
├── README.md                   # 项目说明文件
├── docs/                       # 文档目录
│   └── doc.md                 # 项目文档（本文件）
└── ai-mining/                  # 主要项目目录
    ├── .github/                # GitHub工作流配置
    │   └── workflows/
    ├── .husky/                 # Git钩子配置
    │   ├── _/
    │   └── pre-commit
    ├── .gitmodules             # Git子模块配置
    ├── .lintstagedrc.js        # Lint-staged配置
    ├── .yarnrc.yml             # Yarn配置
    ├── CONTRIBUTING.md         # 贡献指南
    ├── LICENCE                 # 许可证文件
    ├── README.md               # 项目说明
    ├── package.json            # 项目依赖配置
    ├── yarn.lock               # 依赖锁定文件
    ├── docs/                   # 文档目录
    │   └── doc.md              # 智能合约接口文档
    └── packages/               # 主要代码包
        ├── foundry/            # 智能合约包
        │   ├── contracts/      # 智能合约源码
        │   │   ├── NFTStaking.sol      # 主要NFT质押合约
        │   │   ├── OldNFTStaking.sol   # 旧版质押合约
        │   │   ├── interface/          # 接口定义
        │   │   ├── library/            # 库文件
        │   │   └── types.sol           # 类型定义
        │   ├── script/         # 部署脚本
        │   │   ├── Deploy.s.sol
        │   │   ├── DeployHelpers.s.sol
        │   │   ├── UpgradeNFTStaking.s.sol
        │   │   └── VerifyAll.s.sol
        │   ├── scripts-js/     # JavaScript工具脚本
        │   ├── test/           # 测试文件
        │   ├── lib/            # 第三方库
        │   │   ├── forge-std/
        │   │   ├── openzeppelin-contracts/
        │   │   ├── openzeppelin-contracts-upgradeable/
        │   │   └── 其他依赖库...
        │   ├── foundry.toml    # Foundry配置
        │   ├── remappings.txt  # 导入映射
        │   └── package.json    # 包配置
        └── nextjs/             # 前端应用包(仅用于自测)
            ├── app/            # Next.js应用目录
            │   ├── blockexplorer/  # 区块浏览器页面
            │   ├── debug/          # 调试页面
            │   ├── layout.tsx      # 布局组件
            │   ├── not-found.tsx   # 404页面
            │   └── page.tsx        # 主页
            ├── components/     # React组件
            │   ├── Footer.tsx
            │   ├── Header.tsx
            │   ├── scaffold-eth/   # Scaffold-ETH组件
            │   └── 其他组件...
            ├── contracts/      # 合约配置
            ├── hooks/          # React钩子
            ├── services/       # 服务层
            ├── utils/          # 工具函数
            ├── styles/         # 样式文件
            ├── public/         # 静态资源
            └── 配置文件...
```

## 核心功能

### NFTStaking 智能合约

主要合约 `NFTStaking.sol` 提供以下核心功能：

1. **NFT质押系统**
   - 支持ERC1155标准的NFT质押
   - 每台机器最多可质押10个NFT
   - 基础储备金额：100,000 个token

2. **奖励机制**
   - 基于GPU算力的奖励分配
   - 180天锁定期
   - 动态奖励计算

3. **机器管理**
   - 机器注册和状态管理
   - 在线/离线状态跟踪
   - 故障报告机制

4. **安全特性**
   - 可升级代理模式（UUPS）
   - 重入攻击保护
   - 权限控制

### 前端应用(仅用于自测)

基于Next.js构建的现代化Web3前端：

- **钱包集成**: 支持多种钱包连接
- **合约交互**: 自动生成的类型安全钩子
- **实时更新**: 合约热重载功能
- **调试工具**: 内置合约调试界面
- **响应式设计**: 现代化UI/UX

## 开发环境要求

- Node.js >= v20.18.3
- Yarn (v1或v2+)
- Git

## 快速开始

### 1. 安装依赖

```bash
cd ai-mining
yarn install
```

### 2. 启动本地网络

```bash
yarn chain
```

### 3. 部署合约

```bash
yarn deploy
```

### 4. 启动前端

```bash
yarn start
```

## 可用脚本

### 合约相关
- `yarn compile` - 编译智能合约
- `yarn deploy` - 部署合约(dbc mainnet)
- `yarn test` - 运行测试
- `yarn verify` - 验证合约

### 前端相关
- `yarn start` - 启动开发服务器
- `yarn build` - 构建生产版本
- `yarn lint` - 代码检查
- `yarn format` - 代码格式化

### 账户管理
- `yarn account` - 查看账户信息
- `yarn account:generate` - 生成新账户
- `yarn account:import` - 导入账户(*首次部署需要导入用于部署的账户)

## 项目特色

1. **模块化架构**: 清晰的代码组织和模块分离
2. **类型安全**: 全面的TypeScript支持
3. **自动化工具**: 完整的CI/CD流程
4. **开发体验**: 热重载、自动格式化等开发工具
5. **安全性**: 多层安全机制和最佳实践
6. **可扩展性**: 基于代理模式的可升级合约

## 贡献指南

请参考 `CONTRIBUTING.md` 文件了解如何为项目做出贡献。

## 许可证

本项目采用开源许可证，详见 `LICENSE` 文件。

---


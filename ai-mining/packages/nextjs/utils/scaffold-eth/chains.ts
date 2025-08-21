import { defineChain } from "viem";

// DBC Mainnet
export const dbcMainnet = defineChain({
  id: 19880818,
  name: "DBC Mainnet",
  network: "dbc-mainnet",
  nativeCurrency: {
    decimals: 18,
    name: "DBC",
    symbol: "DBC",
  },
  rpcUrls: {
    default: {
      http: ["https://rpc2.dbcwallet.io"],
    },
    public: {
      http: ["https://rpc2.dbcwallet.io"],
    },
  },
  blockExplorers: {
    default: {
      name: "DBC Explorer",
      url: "https://explorer.dbcwallet.io",
    },
  },
});

// DBC Testnet
export const dbcTestnet = defineChain({
  id: 19850818,
  name: "DBC Testnet",
  network: "dbc-testnet",
  nativeCurrency: {
    decimals: 18,
    name: "DBC",
    symbol: "DBC",
  },
  rpcUrls: {
    default: {
      http: ["https://rpc-testnet.dbcwallet.io"],
    },
    public: {
      http: ["https://rpc-testnet.dbcwallet.io"],
    },
  },
  blockExplorers: {
    default: {
      name: "DBC Testnet Explorer",
      url: "https://testnet-explorer.dbcwallet.io",
    },
  },
  testnet: true,
});
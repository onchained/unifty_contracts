import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";

const config: HardhatUserConfig = {
  paths: {
    artifacts: './build'
  },
  solidity: {
    compilers: [
      {
        version: "0.5.17"
      },
      {
        version: "0.6.0",
        settings: { } 
      }
    ]
  }
};

export default config;

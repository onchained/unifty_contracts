import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
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

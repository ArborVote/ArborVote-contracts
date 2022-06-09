import {task} from "hardhat/config";
import "hardhat-gas-reporter";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-solhint";
import { config as dotenvConfig } from 'dotenv'
import { resolve } from 'path'
dotenvConfig({ path: resolve(__dirname, './.env') })

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
    const accounts = await hre.ethers.getSigners();

    for (const account of accounts) {
        console.log(await account.address);
    }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

export default {
    solidity: "0.8.10",
    settings: {
        optimizer: {
            enabled: true,
            runs: 2000
        }
    },
    gasReporter: {
        currency: 'EUR',
        //gasPrice: 30,
        coinmarketcap: process.env.COINMARKETCAP_API_KEY
    }
};


/*
 * NB: since truffle-hdwallet-provider 0.0.5 you must wrap HDWallet providers in a 
 * function when declaring them. Failure to do so will cause commands to hang. ex:
 * ```
 * mainnet: {
 *     provider: function() { 
 *       return new HDWalletProvider(mnemonic, 'https://mainnet.infura.io/<infura-key>') 
 *     },
 *     network_id: '1',
 *     gas: 4500000,
 *     gasPrice: 10000000000,
 *   },
 */
const HDWalletProvider = require("truffle-hdwallet-provider");
const NonceTrackerSubprovider = require("web3-provider-engine/subproviders/nonce-tracker");

var mnemonic = "";

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!

  networks: {
    development: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*"
    },
    kovan: {
      provider: function() {
        var wallet = new HDWalletProvider(mnemonic, "", 0, 1)
        var nonceTracker = new NonceTrackerSubprovider()
        wallet.engine._providers.unshift(nonceTracker)
        nonceTracker.setEngine(wallet.engine)
        return wallet
      },
      gasPrice: 9000000000,
      network_id: "42"// Koven ID 42
     },
     mainnet: {
       provider: function() {
         var wallet = new HDWalletProvider(mnemonic, "", 0, 1)
         var nonceTracker = new NonceTrackerSubprovider()
         wallet.engine._providers.unshift(nonceTracker)
         nonceTracker.setEngine(wallet.engine)
         return wallet
       },
       gasPrice: 20000000000, // 20 gwei
       network_id: "1"// Mainnet ID 1
      }
  },
  // check if needed optimizer, without it contract gets too large and truffle throws : out of gas
  solc: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  }
};

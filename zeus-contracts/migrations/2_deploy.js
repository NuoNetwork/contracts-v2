var Config = artifacts.require("Config");
var DSGuard = artifacts.require("DSGuard");
var AccountFactory = artifacts.require("AccountFactory");
var Reserve = artifacts.require("Reserve");
var ReserveEscrow = artifacts.require("ReserveEscrow");
var KernelEscrow = artifacts.require("KernelEscrow");
var Kernel = artifacts.require("Kernel");
var DateTime = artifacts.require("DateTime");
var Account = artifacts.require("Account");
var KyberConnector = artifacts.require("KyberConnector");
var WETH9 = artifacts.require("WETH9");
var TestToken = artifacts.require("TestToken");

// TODO: separate out deployment in diffrent migration files
module.exports = function(deployer, network, accounts) {
   

    deployer.then(async() => {
        if(network === "mainnet") {
            console.log("<============ using account " + accounts[0] + " for deployment ============>");

            const owner = accounts[0];
            const feeWallet = accounts[0];
            const weth9 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
            var result;
            var count = 0;
            var kyberProxy = "0x818E6FECD516Ecc3849DAf6845e3EC868087B755";
            
            console.log("step" + count++ + " ==> deploying DSGuard");
            var guard = await deployer.deploy(DSGuard);
                
            console.log("step" + count++ + " ==> deploying DateTime");
            var dateTime = await deployer.deploy(DateTime);
            
            // escrow 
            console.log("step" + count++ + " ==> deploying reserve escrow and kernel escrow");
            
            var reserveEscrow = await deployer.deploy(ReserveEscrow);
            reserveEscrow = await ReserveEscrow.at(ReserveEscrow.address); // un necessary, but needed for kovan

            var kernelEscrow = await deployer.deploy(KernelEscrow);
            kernelEscrow = await KernelEscrow.at(KernelEscrow.address);

            console.log("step" + count++ + " ==> config authority for reserve escrow and kernel escrow");
            
            result = await reserveEscrow.setAuthority(DSGuard.address);
            result = await reserveEscrow.setOwner(0);
            result = await kernelEscrow.setAuthority(DSGuard.address);
            result = await kernelEscrow.setOwner(0);

            console.log("step" + count++ + " ==> deploy config");
            var config = await deployer.deploy(Config);
            config = await Config.at(Config.address);

            console.log("step" + count++ + " ==> update params and configure authority for config");
            result = await config.setWETH9(weth9);
            result = await config.setAccountHandler(reserveEscrow.address, true);
            result = await config.setAccountHandler(kernelEscrow.address, true);

            result = await config.setAuthority(DSGuard.address);
            result = await config.setOwner(0);

            console.log("step" + count++ + " ==> deploying account master copy");
            var account = await deployer.deploy(Account);
            account = Account.at(Account.address);
            result = await account.init(owner, Config.address);

            console.log("step" + count++ + " ==> deploying accountFactory");
            var accountFactory = await deployer.deploy(AccountFactory, Config.address, account.address);
            accountFactory = AccountFactory.at(AccountFactory.address);
            
            console.log("step" + count++ + " ==> configure accountFactory");
            result = await accountFactory.setAuthority(DSGuard.address);
            result = await accountFactory.setOwner(0);

            console.log("step" + count++ + " ==> deploying reserve");
            var reserve = await deployer.deploy(Reserve, reserveEscrow.address, AccountFactory.address, DateTime.address, Config.address);
            reserve = Reserve.at(Reserve.address);

            console.log("step" + count++ + " ==> config authority for reserve");
            result = await reserve.setAuthority(DSGuard.address);
            result = await reserve.setOwner(0);

            console.log("step" + count++ + " ==> deploying kyber connector");
            var kyberConnector = await deployer.deploy(KyberConnector, kyberProxy);
            kyberConnector = KyberConnector.at(KyberConnector.address);

            console.log("step" + count++ + " ==> config authority for kyber connector");
            result = await kyberConnector.setAuthority(DSGuard.address);
            result = await kyberConnector.setOwner(0);

            console.log("step" + count++ + " ==> deploying kernel");
            var kernel = await deployer.deploy(Kernel, kernelEscrow.address, AccountFactory.address, Reserve.address, feeWallet, Config.address, KyberConnector.address);
            kernel = Kernel.at(Kernel.address);

            console.log("step" + count++ + " ==> config authority for kernel");
            result = await kernel.setAuthority(DSGuard.address);
            result = await kernel.setOwner(0);
            
            console.log("step" + count++ + " ==> config access controls for contracts");
            guard = await DSGuard.at(DSGuard.address);

            // reserve access
            result = await guard.permit(Reserve.address, reserveEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            result = await guard.permit(Reserve.address, reserveEscrow.address, getMethodSignatureHash("transferFromAccount(address,address,address,uint256)"));
            result = await guard.permit(Reserve.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            
            // kernel
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("release(address,address,uint256)"));
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("lock(address,address,uint256,uint256,uint256)"));
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("lockSurplus(address,address,address,uint256)"));
            result = await guard.permit(Kernel.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            result = await guard.permit(Kernel.address, kernelEscrow.address, getMethodSignatureHash("transferFromAccount(address,address,address,uint256)"));
            result = await guard.permit(Kernel.address, KyberConnector.address, getMethodSignatureHash("trade(address,address,address,uint256,uint256)"));
            
            // kyber connector
            result = await guard.permit(KyberConnector.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            
            // owner access 
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("setAccountMaster(address)"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("stop()"));
            

            result = await guard.permit(owner, Config.address, getMethodSignatureHash("setWETH9(address)"));
            result = await guard.permit(owner, Config.address, getMethodSignatureHash("setAccountHandler(address,bool)"));
            result = await guard.permit(owner, Config.address, getMethodSignatureHash("toggleAdminsControl()"));
            
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setFeeWallet(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setEscrow(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setAccountFactory(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setReserve(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setKyberConnector(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("stop()"));

            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setEscrow(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setAccountFactory(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setDateTime(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("stop()"));

            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("transferSurplus(address,address,address,uint256)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("lock(address,address,uint256,uint256)"));

            result = await guard.permit(owner, KyberConnector.address, getMethodSignatureHash("setKyber(address)"));

            //result = await guard.setOwner(0);
        }
        
        /*
        if(network === "kovan") {
            
            console.log("<============ using account " + accounts[0] + " for deployment ============>");
            const owner = accounts[0];
            const feeWallet = accounts[0];
            const weth9 = "0xd0A1E359811322d97991E03f863a0C30C2cF029C";
            var result;
            var count = 0;
            var kyberProxy = "0x7e6b8b9510D71BF8EF0f893902EbB9C865eEF4Df";
            
            console.log("step" + count++ + " ==> deploying DSGuard");
            var guard = await deployer.deploy(DSGuard);
                
            console.log("step" + count++ + " ==> deploying DateTime");
            var dateTime = await deployer.deploy(DateTime);
            
            // escrow 
            console.log("step" + count++ + " ==> deploying reserve escrow and kernel escrow");
            
            var reserveEscrow = await deployer.deploy(ReserveEscrow);
            reserveEscrow = await ReserveEscrow.at(ReserveEscrow.address); // un necessary, but needed for kovan

            var kernelEscrow = await deployer.deploy(KernelEscrow);
            kernelEscrow = await KernelEscrow.at(KernelEscrow.address);

            console.log("step" + count++ + " ==> config authority for reserve escrow and kernel escrow");
            
            result = await reserveEscrow.setAuthority(DSGuard.address);
            result = await reserveEscrow.setOwner(0);
            result = await kernelEscrow.setAuthority(DSGuard.address);
            result = await kernelEscrow.setOwner(0);

            console.log("step" + count++ + " ==> deploy config");
            var config = await deployer.deploy(Config);
            config = await Config.at(Config.address);

            console.log("step" + count++ + " ==> update params and configure authority for config");
            result = await config.setWETH9(weth9);
            result = await config.setAccountHandler(reserveEscrow.address, true);
            result = await config.setAccountHandler(kernelEscrow.address, true);

            // IMP -> remove in production/mainnet
            result = await config.toggleAdminsControl(); // disabling admin control on contract calls
            result = await config.setAuthority(DSGuard.address);
            result = await config.setOwner(0);

            console.log("step" + count++ + " ==> deploying account master copy");
            var account = await deployer.deploy(Account);
            account = Account.at(Account.address);
            result = await account.init(owner, Config.address);

            console.log("step" + count++ + " ==> deploying accountFactory");
            var accountFactory = await deployer.deploy(AccountFactory, Config.address, account.address);
            accountFactory = AccountFactory.at(AccountFactory.address);
            
            console.log("step" + count++ + " ==> configure accountFactory");
            result = await accountFactory.setAuthority(DSGuard.address);
            result = await accountFactory.setOwner(0);

            console.log("step" + count++ + " ==> deploying reserve");
            var reserve = await deployer.deploy(Reserve, reserveEscrow.address, AccountFactory.address, DateTime.address, Config.address);
            reserve = Reserve.at(Reserve.address);

            console.log("step" + count++ + " ==> config authority for reserve");
            result = await reserve.setAuthority(DSGuard.address);
            result = await reserve.setOwner(0);

            console.log("step" + count++ + " ==> deploying kyber connector");
            var kyberConnector = await deployer.deploy(KyberConnector, kyberProxy);
            kyberConnector = KyberConnector.at(KyberConnector.address);

            console.log("step" + count++ + " ==> config authority for kyber connector");
            result = await kyberConnector.setAuthority(DSGuard.address);
            result = await kyberConnector.setOwner(0);

            console.log("step" + count++ + " ==> deploying kernel");
            var kernel = await deployer.deploy(Kernel, kernelEscrow.address, AccountFactory.address, Reserve.address, feeWallet, Config.address, KyberConnector.address);
            kernel = Kernel.at(Kernel.address);

            console.log("step" + count++ + " ==> config authority for kernel");
            result = await kernel.setAuthority(DSGuard.address);
            result = await kernel.setOwner(0);
            
            console.log("step" + count++ + " ==> config access controls for contracts");
            guard = await DSGuard.at(DSGuard.address);

            // reserve access
            result = await guard.permit(Reserve.address, reserveEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            result = await guard.permit(Reserve.address, reserveEscrow.address, getMethodSignatureHash("transferFromAccount(address,address,address,uint256)"));
            result = await guard.permit(Reserve.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            
            // kernel
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("release(address,address,uint256)"));
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("lock(address,address,uint256,uint256,uint256)"));
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("lockSurplus(address,address,address,uint256)"));
            result = await guard.permit(Kernel.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            result = await guard.permit(Kernel.address, kernelEscrow.address, getMethodSignatureHash("transferFromAccount(address,address,address,uint256)"));
            result = await guard.permit(Kernel.address, KyberConnector.address, getMethodSignatureHash("trade(address,address,address,uint256,uint256)"));
            
            // kyber connector
            result = await guard.permit(KyberConnector.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            
            // owner access 
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("setAccountMaster(address)"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("stop()"));
            

            result = await guard.permit(owner, Config.address, getMethodSignatureHash("setWETH9(address)"));
            result = await guard.permit(owner, Config.address, getMethodSignatureHash("setAccountHandler(address,bool)"));
            result = await guard.permit(owner, Config.address, getMethodSignatureHash("toggleAdminsControl()"));
            
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setFeeWallet(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setEscrow(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setAccountFactory(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setReserve(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setKyberConnector(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("stop()"));

            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setEscrow(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setAccountFactory(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setDateTime(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("stop()"));

            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("transferSurplus(address,address,address,uint256)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("lock(address,address,uint256,uint256)"));

            result = await guard.permit(owner, KyberConnector.address, getMethodSignatureHash("setKyber(address)"));

            //result = await guard.setOwner(0);
        }
        */
        /*
        if(network === "development") {

            console.log("<============ using account " + accounts[0] + " for deployment ============>");

            const owner = accounts[0];
            const feeWallet = accounts[0];
            var result;
            var count = 0;
            var kyberProxy = "0x7e6b8b9510D71BF8EF0f893902EbB9C865eEF4Df"; // randon for now, will onot work
            
            console.log("step" + count++ + " ==> deploying WETH9");
            const weth9 = await deployer.deploy(WETH9);

            console.log("step" + count++ + " ==> deploying TestToken");
            const testToken = await deployer.deploy(TestToken);

            console.log("step" + count++ + " ==> deploying DSGuard");
            var guard = await deployer.deploy(DSGuard);
                
            console.log("step" + count++ + " ==> deploying DateTime");
            var dateTime = await deployer.deploy(DateTime);
            
            // escrow 
            console.log("step" + count++ + " ==> deploying reserve escrow and kernel escrow");
            
            var reserveEscrow = await deployer.deploy(ReserveEscrow);
            reserveEscrow = await ReserveEscrow.at(ReserveEscrow.address); // un necessary, but needed for kovan

            var kernelEscrow = await deployer.deploy(KernelEscrow);
            kernelEscrow = await KernelEscrow.at(KernelEscrow.address);

            console.log("step" + count++ + " ==> config authority for reserve escrow and kernel escrow");
            
            result = await reserveEscrow.setAuthority(DSGuard.address);
            result = await reserveEscrow.setOwner(0);

            result = await kernelEscrow.setAuthority(DSGuard.address);
            result = await kernelEscrow.setOwner(0);

            console.log("step" + count++ + " ==> deploy config");
            var config = await deployer.deploy(Config);
            config = await Config.at(Config.address);

            console.log("step" + count++ + " ==> update params and configure authority for config");
            result = await config.setWETH9(weth9.address);
            result = await config.setAccountHandler(reserveEscrow.address, true);
            result = await config.setAccountHandler(kernelEscrow.address, true);

            // IMP -> remove in production/mainnet
            result = await config.toggleAdminsControl(); // disabling admin control on contract calls
            result = await config.setAuthority(DSGuard.address);
            result = await config.setOwner(0);
            
            console.log("step" + count++ + " ==> deploying account master copy");
            var account = await deployer.deploy(Account);
            account = Account.at(Account.address);

            result = await account.init(owner, Config.address);
            

            console.log("step" + count++ + " ==> deploying accountFactory");
            var accountFactory = await deployer.deploy(AccountFactory, Config.address, account.address);
            accountFactory = AccountFactory.at(AccountFactory.address);
            
            console.log("step" + count++ + " ==> configure accountFactory");
            result = await accountFactory.setAuthority(DSGuard.address);

            result = await accountFactory.setOwner(0);

            console.log("step" + count++ + " ==> deploying reserve");
            var reserve = await deployer.deploy(Reserve, reserveEscrow.address, AccountFactory.address, DateTime.address, Config.address);
            reserve = Reserve.at(Reserve.address);

            console.log("step" + count++ + " ==> config authority for reserve");
            result = await reserve.setAuthority(DSGuard.address);
            result = await reserve.setOwner(0);

            console.log("step" + count++ + " ==> deploying kyber connector");
            var kyberConnector = await deployer.deploy(KyberConnector, kyberProxy);
            kyberConnector = KyberConnector.at(KyberConnector.address);

            console.log("step" + count++ + " ==> config authority for kyber connector");
            result = await kyberConnector.setAuthority(DSGuard.address);
            result = await kyberConnector.setOwner(0);

            console.log("step" + count++ + " ==> deploying kernel");
            var kernel = await deployer.deploy(Kernel, kernelEscrow.address, AccountFactory.address, Reserve.address, feeWallet, Config.address, KyberConnector.address);
            kernel = Kernel.at(Kernel.address);

            console.log("step" + count++ + " ==> config authority for kernel");
            result = await kernel.setAuthority(DSGuard.address);
            result = await kernel.setOwner(0);
            
            console.log("step" + count++ + " ==> config access controls for contracts");
            guard = await DSGuard.at(DSGuard.address);

            // reserve access
            result = await guard.permit(Reserve.address, reserveEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            result = await guard.permit(Reserve.address, reserveEscrow.address, getMethodSignatureHash("transferFromAccount(address,address,address,uint256)"));
            result = await guard.permit(Reserve.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            
            // kernel
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("release(address,address,uint256)"));
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("lock(address,address,uint256,uint256,uint256)"));
            result = await guard.permit(Kernel.address, Reserve.address, getMethodSignatureHash("lockSurplus(address,address,address,uint256)"));
            result = await guard.permit(Kernel.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            result = await guard.permit(Kernel.address, kernelEscrow.address, getMethodSignatureHash("transferFromAccount(address,address,address,uint256)"));
            result = await guard.permit(Kernel.address, KyberConnector.address, getMethodSignatureHash("trade(address,address,address,uint256,uint256)"));
            
            // kyber connector
            result = await guard.permit(KyberConnector.address, kernelEscrow.address, getMethodSignatureHash("transfer(address,address,uint256)"));
            
            // owner access 
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("setAccountMaster(address)"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, AccountFactory.address, getMethodSignatureHash("stop()"));
            

            result = await guard.permit(owner, Config.address, getMethodSignatureHash("setWETH9(address)"));
            result = await guard.permit(owner, Config.address, getMethodSignatureHash("setAccountHandler(address,bool)"));
            result = await guard.permit(owner, Config.address, getMethodSignatureHash("toggleAdminsControl()"));
            
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setFeeWallet(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setEscrow(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setAccountFactory(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setReserve(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("setKyberConnector(address)"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, Kernel.address, getMethodSignatureHash("stop()"));

            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setEscrow(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setAccountFactory(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setDateTime(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("setConfig(address)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("start()"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("stop()"));

            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("transferSurplus(address,address,address,uint256)"));
            result = await guard.permit(owner, Reserve.address, getMethodSignatureHash("lock(address,address,uint256,uint256)"));

            result = await guard.permit(owner, KyberConnector.address, getMethodSignatureHash("setKyber(address)"));

            //result = await guard.setOwner(0);
        }
        */
    });

    function getMethodSignatureHash(method) {
        return web3.sha3(method).slice(0,10); // to handle bytes4 and signature match
    }
    
};
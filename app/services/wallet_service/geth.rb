# encoding: UTF-8
# frozen_string_literal: true

module WalletService
  class Geth < Base

    DEFAULT_ETH_FEE = { gas_limit: 21_000, gas_price: 10_000_000_000 }.freeze

    DEFAULT_ERC20_FEE_VALUE =  100_000 * DEFAULT_ETH_FEE[:gas_price]

    def create_address(options = {})
      client.create_address!(options)
    end

    def collect_deposit!(deposit, options={})
      destination_wallets = destination_wallets(deposit)
      if deposit.currency.code.eth?
        collect_eth_deposit!(deposit, destination_wallets, options)
      else
        collect_erc20_deposit!(deposit, destination_wallets, options)
      end
    end

    def build_withdrawal!(withdraw)
      if withdraw.currency.code.eth?
        build_eth_withdrawal!(withdraw)
      else
        build_erc20_withdrawal!(withdraw)
      end
    end

    def deposit_collection_fees(deposit, value=DEFAULT_ERC20_FEE_VALUE, options={})
      fees_wallet = eth_fees_wallet
      destination_address = deposit.account.payment_address.address
      options = DEFAULT_ETH_FEE.merge options

      client.create_eth_withdrawal!(
        { address: fees_wallet.address, secret: fees_wallet.secret },
        { address: destination_address },
        value,
        options
      )
    end

    private

    def eth_fees_wallet
      Wallet
        .active
        .withdraw
        .find_by(currency_id: :eth, kind: :hot)
    end

    def collect_eth_deposit!(deposit, destination_wallets, options={})
      # Default values for Ethereum tx fees.
      options = DEFAULT_ETH_FEE.merge options

      # We can't collect all funds we need to subtract gas fees.
      deposit_amount = deposit.amount_to_base_unit! - options[:gas_limit] * options[:gas_price]
      pa = deposit.account.payment_address
      destination_wallets.each do |wallet|
        max_wallet_amount = (wallet.max_balance * Currency.find(wallet.currency_id).base_factor).to_i
        break if deposit_amount == 0
        wallet_balance = client.load_balance!(wallet.address).to_i
        if wallet_balance + deposit_amount > max_wallet_amount
          amount_left = max_wallet_amount - wallet_balance
          next if amount_left < Currency.find(wallet.currency_id).min_deposit_amount
          client.create_eth_withdrawal!(
              { address: pa.address, secret: pa.secret },
              { address: wallet.address },
              amount_left,
              options
          )
          deposit_amount -= amount_left
        else
          client.create_eth_withdrawal!(
              { address: pa.address, secret: pa.secret },
              { address: wallet.address },
              deposit_amount,
              options
          )
          break
        end
      end
    end

    def collect_erc20_deposit!(deposit, destination_wallets, options={})
      pa = deposit.account.payment_address

      deposit_amount = deposit.amount_to_base_unit!
      destination_wallets.each do |wallet|
        max_wallet_amount = (wallet.max_balance * Currency.find(wallet.currency_id).base_factor).to_i
        break if deposit_amount == 0
        wallet_balance = client.load_balance!(wallet.address).to_i
        if wallet_balance + deposit_amount > max_wallet_amount
          amount_left = max_wallet_amount - wallet_balance
          next if amount_left < Currency.find(wallet.currency_id).min_deposit_amount
          client.create_erc20_withdrawal!(
              { address: pa.address, secret: pa.secret },
              { address: wallet.address },
              amount_left,
              options.merge(contract_address: deposit.currency.erc20_contract_address )
          )
          deposit_amount -= amount_left
        else
          client.create_erc20_withdrawal!(
              { address: pa.address, secret: pa.secret },
              { address: wallet.address },
              deposit_amount,
              options.merge(contract_address: deposit.currency.erc20_contract_address )
          )
          break
        end
      end
    end

    def build_eth_withdrawal!(withdraw)
      client.create_eth_withdrawal!(
        { address: wallet.address, secret: wallet.secret },
        { address: withdraw.rid },
        withdraw.amount_to_base_unit!
      )
    end

    def build_erc20_withdrawal!(withdraw)
      client.create_erc20_withdrawal!(
        { address: wallet.address, secret: wallet.secret },
        { address: withdraw.rid },
        withdraw.amount_to_base_unit!,
        {contract_address: withdraw.currency.erc20_contract_address}
      )
    end
  end
end
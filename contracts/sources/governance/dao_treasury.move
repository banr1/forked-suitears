module suitears::dao_treasury { 
  use std::type_name::{Self, TypeName};

  use sui::event::emit;
  use sui::clock::Clock;
  use sui::bag::{Self, Bag};
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::balance::{Self, Balance};
  use sui::tx_context::{Self, TxContext};

  use suitears::dao_admin::DaoAdmin;
  use suitears::fixed_point_roll::mul_up;
  use suitears::linear_vesting_wallet::{Self, Wallet as LinearWallet};

  friend suitears::dao;

  const FLASH_LOAN_FEE: u64 = 5000000; // 0.5%

  const ERepayAmountTooLow: u64 = 0;

  struct DaoTreasury<phantom DaoWitness: drop> has key, store {
    id: UID,
    coins: Bag,
    dao: ID,
  }

  // * IMPORTANT do not add abilities 
  struct FlashLoan<phantom DaoWitness, phantom CoinType> {
    initial_balance: u64,
    fee: u64,
    type: TypeName
  }

  // Events

  struct Donate<phantom DaoWitness, phantom CoinType> has copy, drop {
    value: u64,
    donator: address  
  }

  struct Transfer<phantom DaoWitness, phantom CoinType> has copy, drop {
    value: u64,
    sender: address
  }
  
  struct TransferLinearWallet<phantom DaoWitness, phantom CoinType> has copy, drop {
    value: u64,
    sender: address,
    wallet_id: ID,
    start: u64,
    duration: u64
  }

  struct FlashLoanRequest<phantom DaoWitness, phantom CoinType> has copy, drop {
    borrower: address,
    treasury_id: ID,
    value: u64,
    type: TypeName
  } 

  public(friend) fun create<DaoWitness: drop>(dao: ID, ctx: &mut TxContext): DaoTreasury<DaoWitness> {
    DaoTreasury {
      id: object::new(ctx),
      coins: bag::new(ctx),
      dao
    }
  }

  public fun donate<DaoWitness: drop, CoinType>(treasury: &mut DaoTreasury<DaoWitness>, token: Coin<CoinType>, ctx: &mut TxContext) {
    let key = type_name::get<CoinType>();
    let value = coin::value(&token);

    if (!bag::contains(&treasury.coins, key)) {
      bag::add(&mut treasury.coins, key, coin::into_balance(token))
    } else {
      balance::join(bag::borrow_mut<TypeName, Balance<CoinType>>(&mut treasury.coins, key), coin::into_balance(token));
    };

    emit(Donate<DaoWitness, CoinType> { value, donator: tx_context::sender(ctx) });
  }

  public fun view_coin_balance<DaoWitness: drop, CoinType>(treasury: &DaoTreasury<DaoWitness>): u64 {
    balance::value(bag::borrow<TypeName, Balance<CoinType>>(&treasury.coins, type_name::get<CoinType>()))
  }

  public fun transfer<DaoWitness: drop, CoinType, TransferCoin>(
    treasury: &mut DaoTreasury<DaoWitness>,
    _: &DaoAdmin<DaoWitness>,
    value: u64,
    ctx: &mut TxContext
  ): Coin<CoinType> {
    
    let token = coin::take(bag::borrow_mut(&mut treasury.coins, type_name::get<TransferCoin>()), value, ctx);

    emit(Transfer<DaoWitness, CoinType> { 
        value: value, 
        sender: tx_context::sender(ctx) 
      }
    );

    token
  }

  public fun transfer_linear_vesting_wallet<DaoWitness: drop, CoinType, TransferCoin>(
    treasury: &mut DaoTreasury<DaoWitness>,
    _: &DaoAdmin<DaoWitness>,
    c: &Clock,
    value: u64,
    start: u64,
    duration: u64,
    ctx: &mut TxContext    
  ): LinearWallet<CoinType> {
    
    let token = coin::take<CoinType>(bag::borrow_mut(&mut treasury.coins, type_name::get<TransferCoin>()), value, ctx);

    let wallet = linear_vesting_wallet::new(token, c, start, duration, ctx);

    emit(TransferLinearWallet<DaoWitness, CoinType> { 
        value, 
        sender: tx_context::sender(ctx), 
        duration, 
        start, 
        wallet_id: object::id(&wallet) 
      }
    );
    
    wallet
  }

  // Flash loan logic

  public fun flash_loan<DaoWitness: drop, CoinType>(
    treasury: &mut DaoTreasury<DaoWitness>, 
    value: u64, 
    ctx: &mut TxContext
  ): (Coin<CoinType>, FlashLoan<DaoWitness, CoinType>) {

    let type = type_name::get<CoinType>();
    let initial_balance = balance::value(bag::borrow<TypeName, Balance<CoinType>>(&treasury.coins, type));

    emit(FlashLoanRequest<DaoWitness, CoinType> { type, borrower: tx_context::sender(ctx), value, treasury_id: object::id(treasury) });

    (
      coin::take<CoinType>(bag::borrow_mut(&mut treasury.coins, type), value, ctx),
      FlashLoan { initial_balance , type, fee: mul_up(value, FLASH_LOAN_FEE) }
    )
  }

  public fun view_flash_loan<DaoWitness: drop, CoinType>(flash_loan: &FlashLoan<DaoWitness, CoinType>): (TypeName, u64) {
    (flash_loan.type, flash_loan.fee)
  }

  public fun repay_flash_loan<DaoWitness: drop, CoinType>(
    treasury: &mut DaoTreasury<DaoWitness>, 
    flash_loan: FlashLoan<DaoWitness, CoinType>,
    token: Coin<CoinType>
  ) {
    let FlashLoan { initial_balance, type, fee } = flash_loan;
    assert!(coin::value(&token) >= initial_balance + fee, ERepayAmountTooLow);

    balance::join(bag::borrow_mut(&mut treasury.coins, type), coin::into_balance(token));
  }
}

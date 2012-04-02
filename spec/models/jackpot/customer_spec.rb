require 'spec_helper'
require 'timecop'

describe Jackpot::Customer do
  it { should     belong_to                :subscription             } 
  it { should     have_many(:payments).through(:subscription)        }

  it { should_not allow_mass_assignment_of :credit_card_number       } 
  it { should_not allow_mass_assignment_of :credit_card_expiry_year  } 
  it { should_not allow_mass_assignment_of :credit_card_expiry_month } 
  it { should_not allow_mass_assignment_of :credit_card_token        } 

  let(:customer)      { Jackpot::Customer.new } 
  let(:card)          { Jackpot::Card.new credit_card_hash } 
  let(:invalid_card)  { Jackpot::Card.new credit_card_hash('9', :year => '2000') } 

  describe ".expiration_date" , :vcr => { :cassette_name => "jackpot/customer_expiration_date" } do
    it "should return this card expiration date" do
      customer.update_credit_card(card)
      customer.expiration_date.should == "1/#{next_year}"
    end 
  end 


  describe ".overdue" do
    before do
      Timecop.freeze(Date.today) do
        @today       = FactoryGirl.create(:customer, :good_until => Date.today)
        @tomorrow    = FactoryGirl.create(:customer, :good_until => Date.tomorrow)
        @yesterday   = FactoryGirl.create(:customer, :good_until => Date.yesterday)
      end 
    end 
    
    subject { Jackpot::Customer.overdue} 

    it { subject.should     include @yesterday } 
    it { subject.should_not include @tomorrow  } 
    it { subject.should_not include @today     } 
    
  end 

  describe ".due_in" do
    before do
      Timecop.freeze(Date.today) do
        @next_week    = FactoryGirl.create(:customer, :good_until => 1.week.from_now)
        @thirty_days  = FactoryGirl.create(:customer, :good_until => 30.days.from_now)
        @two_days     = FactoryGirl.create(:customer, :good_until => 2.days.from_now)
        @tomorrow     = FactoryGirl.create(:customer, :good_until => Date.tomorrow)
      end 
    end 

    context "two days" do 
      subject { Jackpot::Customer.due_in 2} 

      it { subject.should     include @tomorrow    } 
      it { subject.should     include @two_days    } 
      it { subject.should_not include @thirty_days } 
      it { subject.should_not include @next_week   } 
    end 
      
  end 


  describe ".pay_subscription" do 
    let(:customer)                       { FactoryGirl.create(:customer_with_subscription, 
                                                :credit_card_token => '42') }

    let(:customer_with_no_card_saved)    { FactoryGirl.create(:customer_with_subscription) } 
    let(:customer_without_subscription)  { FactoryGirl.create(:customer_with_valid_card) } 

    it "fetches charges this customer subscription using his/hers credit card token" do
      customer.subscription.should_receive(:charge).with(customer).and_return(true)
      customer.pay_subscription
    end

    it "sets this customer as not due until the next billing period" do
      customer.subscription.stub(:charge).with(customer).and_return(true)
      customer.pay_subscription

      retrieved_customer = Jackpot::Customer.find(customer)
      retrieved_customer.good_until.should == Date.today + 1.month
    end 

    it { expect { customer_with_no_card_saved.pay_subscription }.to raise_error(Jackpot::Errors::CustomerHasNoCardSaved) }


    context "when there is no subscription assigned" , :vcr do
      it "doesn't throw a no method error" do
        expect { customer_without_subscription.pay_subscription }.to_not raise_error
      end 

      it "doesn't updates the good_until date" do
        expect { customer_without_subscription.pay_subscription }.should_not change(customer_without_subscription, :good_until)
      end 

    end 

  end 

  describe ".update_credit_card_number" do

    context "when card is invalid" do
      it "raises invalid card exception" do
        expect { customer.update_credit_card(invalid_card)}.to raise_error(Jackpot::Errors::CardIsInvalid)
      end 

      it "shouldn't be persisted" do
        expect { customer.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end 

    end 

    context "when card is valid", :vcr => { :cassette_name => "jackpot/customer/updatecard" } do
      before(:each) do 
        customer.update_credit_card(card)
      end 

      it "should masquerade the card number" do
        customer.credit_card_number.should                == 'XXXX-XXXX-XXXX-4242'
      end 

      it { customer.credit_card_expiry_month.should       == 1          } 
      it { customer.credit_card_expiry_year.should        == next_year  } 

      context "when persisting" do

        let(:retrieved_customer) { Jackpot::Customer.find customer } 

        it "should store this card at the gateway" do
          retrieved_customer.credit_card_token.should_not be_nil
        end 

        it "should persist in the database the ONLY last four digits" do
          retrieved_customer.credit_card_number.should == 'XXXX-XXXX-XXXX-4242'
        end 

        it "should NEVER persist in the database the actual card number" do
          retrieved_customer.credit_card_number.should_not  == credit_card_hash[:number]
        end 

        it "should NEVER persist in the database the verification value" do 
          retrieved_customer.credit_card_verification_value.should_not == 123       
          retrieved_customer.credit_card_verification_value.should be_nil
        end

      end 
    end
  end 

end 

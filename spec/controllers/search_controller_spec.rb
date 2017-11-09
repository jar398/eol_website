require 'rails_helper'

RSpec.describe SearchController do


  let(:page) { create(:page) }
  let(:pages) { fake_search_results([page]) }
  let(:collections) { fake_search_results([]) }
  let(:media) { fake_search_results([]) }
  let(:users) { fake_search_results([]) }
  let(:suggestions) { fake_search_results([SearchSuggestion.create(object_term: "something", match: "match")]) }

  before do
    allow(Page).to receive(:search) { pages }
    allow(Collection).to receive(:search) { collections }
    allow(User).to receive(:search) { users }
    allow(SearchSuggestion).to receive(:search) { [] }
    allow(Searchkick).to receive(:search) { media } # NOTE: Media uses multi-index search
    allow(TraitBank).to receive(:search_object_terms) { [] }
    allow(TraitBank).to receive(:search_predicate_terms) { [] }
    allow(TraitBank).to receive(:count_object_terms) { 0 }
    allow(TraitBank).to receive(:count_predicate_terms) { 0 }
    allow(Searchkick).to receive(:multi_search) { }
  end

  describe "#show" do

    context "when requesting all results" do
      before { get :search, q: "query" }
      it { expect(assigns(:pages)).to eq(pages) }
      it { expect(assigns(:collections)).to eq(collections) }
      it { expect(assigns(:media)).to eq(media) }
      it { expect(assigns(:users)).to eq(users) }
      it { expect(assigns(:empty)).to eq(false) }
      it { expect(assigns(:q)).to eq("query") }
      it { expect(Page).to have_received(:search) }
    end

    context "when only requesting pages" do
      before { get :search, q: "query", only: "pages" }
      it { expect(Collection).not_to have_received(:search) }
    end

    context "when requesting all except collections" do
      before { get :search, q: "query", except: ["collections", "object_terms"] }
      it { expect(Collection).not_to have_received(:search) }
    end
  end
end
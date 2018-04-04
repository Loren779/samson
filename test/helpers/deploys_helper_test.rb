# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered! uncovered: 1

describe DeploysHelper do
  include StatusHelper

  let(:deploy) { deploys(:succeeded_test) }

  describe "#deploy_output" do
    let(:output) { 'This worked!' }

    before do
      @deploy = deploy
      @project = deploy.project
      ActionView::Base.any_instance.stubs(current_user: users(:deployer))
    end

    it "renders output when deploy is finished" do
      deploy_output.must_include output
    end

    describe "pending job" do
      let(:result) { deploy_output }

      before { deploy.job.status = 'pending' }

      it "renders restart warning when deploy is waiting for restart" do
        result.wont_include output
        result.must_include 'Deploy is queued and will be started when Samson finishes restarting'
      end

      describe "when jobs are executing" do
        with_job_execution

        it "renders error when job is pending but not queued" do
          result.wont_include output
          result.must_include 'Deploy is pending but not queued or executing, so it will never start.'
        end

        it "renders active warning when job is active" do
          deploy.job.stubs(executing?: true)
          result.wont_include output
          result.must_include 'Deploy is running, refresh this page'
        end

        it "renders queued warning when job is waiting to be executed" do
          deploy.job.stubs(queued?: true)
          result.wont_include output
          result.must_include 'previous deploys have finished'
        end
      end

      it "renders buddy check when waiting for buddy" do
        stub_github_api "repos/bar/foo/commits/staging/status", state: "success", statuses: {}
        deploy.expects(:waiting_for_buddy?).returns(true)
        result.wont_include output
        result.must_include 'This deploy requires a buddy.'
      end
    end
  end

  describe "#deploy_page_title" do
    it "renders" do
      @deploy = deploy
      @project = projects(:test)
      deploy_page_title.must_equal "Staging deploy - Foo"
    end
  end

  describe "#deploy_notification" do
    it "renders a notification" do
      @project = projects(:test)
      @deploy = deploy
      deploy_notification.must_equal "Samson deploy finished:\nFoo / Staging succeeded"
    end
  end

  describe '#syntax_highlight' do
    it "renders code" do
      syntax_highlight("puts 1").must_equal "puts <span class=\"integer\">1</span>"
    end
  end

  describe "#file_status_label" do
    it "shows added" do
      file_status_label('added').must_equal "<span class=\"label label-success\">A</span>"
    end

    it "shows removed" do
      file_status_label('removed').must_equal "<span class=\"label label-danger\">R</span>"
    end

    it "shows modified" do
      file_status_label('modified').must_equal "<span class=\"label label-info\">M</span>"
    end

    it "shows changed" do
      file_status_label('changed').must_equal "<span class=\"label label-info\">C</span>"
    end

    it "shows renamed" do
      file_status_label('renamed').must_equal "<span class=\"label label-info\">R</span>"
    end

    it "fails on unknown" do
      assert_raises(KeyError) { file_status_label('wut') }
    end
  end

  describe "#file_changes_label" do
    it "renders new label" do
      file_changes_label(1, "foo").must_equal "<span class=\"label foo\">1</span>"
    end

    it "does not render new label when count is zero" do
      file_changes_label(0, "bar").must_equal nil
    end
  end

  describe "#github_users" do
    it "renders users' avatar" do
      result = github_users(
        [
          stub(url: 'foourl', login: 'foologin', avatar_url: 'fooavatar'),
          stub(url: 'barurl', login: 'bar"<script>login', avatar_url: 'baravatar'),
        ]
      )
      result.must_equal(
        "<a title=\"foologin\" href=\"foourl\">" \
          "<img width=\"20\" height=\"20\" src=\"/images/fooavatar\" alt=\"Fooavatar\" />" \
        "</a> " \
        "<a title=\"bar&quot;&lt;script&gt;login\" href=\"barurl\">" \
          "<img width=\"20\" height=\"20\" src=\"/images/baravatar\" alt=\"Baravatar\" />" \
        "</a>"
      )
      result.html_safe?.must_equal true
    end

    it "ignores nils" do
      github_users([nil, nil]).must_equal " "
    end
  end

  describe "#redeploy_button" do
    let(:redeploy_warning) { "Why? This deploy succeeded." }

    before do
      @deploy = deploy
      @project = projects(:test)
    end

    it "generates a link" do
      link = redeploy_button
      link.must_include redeploy_warning # warns about redeploying
      link.must_include "?deploy%5Bkubernetes_reuse_build%5D=false" \
        "&amp;deploy%5Bkubernetes_rollback%5D=true&amp;deploy%5Breference%5D=staging\"" # copies params
      link.must_include "Redeploy"
    end

    it 'does not generate a link when deploy is active' do
      deploy.job.stubs(active?: true)
      redeploy_button.must_be_nil
    end

    it "generates a red link when deply failed" do
      deploy.stubs(succeeded?: false)
      redeploy_button.must_include "btn-danger"
      redeploy_button.wont_include redeploy_warning
    end

    context "when a plugin includes extra permitted params" do
      before do
        Samson::Hooks.stubs(fire: extra_params)
      end

      context "when the deploy has a has_many relation" do
        let(:extra_params) { [{ items_attributes: [:uuid, :name] }] }
        let(:items) { [OpenStruct.new(uuid: "xyz", name: "item 1")] }

        before do
          @deploy.stubs(items: items)
        end

        let(:href)   { /href=\"([^"]*)\"/.match(redeploy_button)[1] }
        let(:uri)    { URI.parse(CGI.unescape(href)) }
        let(:params) { CGI.parse(uri.query).to_a }

        it "generates a link with the environment variables and the rest of params" do
          params.must_include(
            ["deploy[items_attributes][][uuid]", ["xyz"]]
          )
          params.must_include(
            ["deploy[items_attributes][][name]", ["item 1"]]
          )
          params.must_include(
            ["deploy[reference]", ["staging"]]
          )
        end
      end
    end

    context "unrecognized deploy hash params" do
      before do
        Samson::Hooks.callback :deploy_permitted_params do
          [{'invalid_hash' => 'one'}]
        end
      end

      it "generates a link and the invalid params are ignored" do
        link = redeploy_button
        link.must_include "?deploy%5Bkubernetes_reuse_build%5D=false" \
          "&amp;deploy%5Bkubernetes_rollback%5D=true&amp;deploy%5Breference%5D=staging\""
      end
    end

    context "invalid deploy param class" do
      before do
        Samson::Hooks.stubs(fire: [[['invalid_array_params']]])
      end

      it "raises an exception" do
        error = -> { redeploy_button }.must_raise RuntimeError
        error.message.must_equal(
          "Unsupported deploy param class: `Array` for `[\"invalid_array_params\"]`."
        )
      end
    end
  end

  describe "#cancel_button" do
    before { stubs(request: stub(fullpath: '/hello')) }

    it "builds with a deploy" do
      button = cancel_button(deploy: deploy, project: deploy.project)
      button.must_include ">Cancel<"
      button.must_include "?redirect_to=%2Fhello\""
    end

    it "builds with a job" do
      button = cancel_button(deploy: deploy.job, project: deploy.project)
      button.must_include ">Cancel<"
    end
  end

  describe "#favicon" do
    it 'returns pending favicon if deploy is active' do
      deploy.job = jobs(:running_test)

      deploy_favicon_path(deploy).must_equal "/images/favicons/32x32_yellow.png"
    end

    it 'returns succeeded favicon if deploy was successful' do
      deploy_favicon_path(deploy).must_equal "/images/favicons/32x32_green.png"
    end

    it 'returns failed favicon if deploy failed' do
      deploy.job = jobs(:failed_test)

      deploy_favicon_path(deploy).must_equal "/images/favicons/32x32_red.png"
    end
  end
end

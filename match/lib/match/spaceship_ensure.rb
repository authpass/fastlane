require 'spaceship'
require_relative 'module'

module Match
  # Ensures the certificate and profiles are also available on App Store Connect
  class SpaceshipEnsure
    def initialize(user, team_id, team_name)
      # We'll try to manually fetch the password
      # to tell the user that a password is optional
      require 'credentials_manager/account_manager'

      keychain_entry = CredentialsManager::AccountManager.new(user: user)

      if keychain_entry.password(ask_if_missing: false).to_s.length == 0
        UI.important("You can also run `fastlane match` in readonly mode to not require any access to the")
        UI.important("Developer Portal. This way you only share the keys and credentials")
        UI.command("fastlane match --readonly")
        UI.important("More information https://docs.fastlane.tools/actions/match/#access-control")
      end

      UI.message("Verifying that the certificate and profile are still valid on the Dev Portal...")
      Spaceship::ConnectAPI.login(use_portal: true, use_tunes: false)
      Spaceship::ConnectAPI.select_team
    end

    # The team ID of the currently logged in team
    def team_id
      return Spaceship::ConnectAPI.client.team_id
    end

    def bundle_identifier_exists(username: nil, app_identifier: nil, platform: nil)
      found = Spaceship::ConnectAPI::BundleId.find(app_identifier)
      return if found

      require 'sigh/runner'
      Sigh::Runner.new.print_produce_command({
        username: username,
        app_identifier: app_identifier
      })
      UI.error("An app with that bundle ID needs to exist in order to create a provisioning profile for it")
      UI.error("================================================================")
      available_apps = Spaceship::ConnectAPI::BundleId.all.collect { |a| "#{a.identifier} (#{a.name})" }
      UI.message("Available apps:\n- #{available_apps.join("\n- ")}")
      UI.error("Make sure to run `fastlane match` with the same user and team every time.")
      UI.user_error!("Couldn't find bundle identifier '#{app_identifier}' for the user '#{username}'")
    end

    def certificates_exists(username: nil, certificate_ids: [], platform: nil)
      if platform == :catalyst.to_s
        platform = :macos.to_s
      end

      Spaceship.certificate.all(mac: platform == "macos").each do |cert|
        certificate_ids.delete(cert.id)
      end
      return if certificate_ids.empty?

      certificate_ids.each do |certificate_id|
        UI.error("Certificate '#{certificate_id}' (stored in your storage) is not available on the Developer Portal")
      end
      UI.error("for the user #{username}")
      UI.error("Make sure to use the same user and team every time you run 'match' for this")
      UI.error("Git repository. This might be caused by revoking the certificate on the Dev Portal")
      UI.user_error!("To reset the certificates of your Apple account, you can use the `fastlane match nuke` feature, more information on https://docs.fastlane.tools/actions/match/")
    end

    def profile_exists(username: nil, uuid: nil, platform: nil)
      # App Store Connect API does not allow filter of profile by platform or uuid (as of 2020-07-30)
      # Need to fetch all profiles and search for uuid on client side
      found = Spaceship::ConnectAPI::Profile.all.find do |profile|
        profile.uuid == uuid
      end

      unless found
        UI.error("Provisioning profile '#{uuid}' is not available on the Developer Portal for the user #{username}, fixing this now for you 🔨")
        return false
      end

      if found.valid?
        return found
      else
        UI.important("'#{found.name}' is available on the Developer Portal, however it's 'Invalid', fixing this now for you 🔨")
        # it's easier to just create a new one, than to repair an existing profile
        # it has the same effects anyway, including a new UUID of the provisioning profile
        found.delete!
        # return nil to re-download the new profile in runner.rb
        return nil
      end
    end
  end
end

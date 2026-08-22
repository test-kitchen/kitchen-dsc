# Contributing to kitchen-dsc

> **This project is no longer under active development** and has no active
> maintainers. Issues filed on GitHub will most likely not be triaged. Pull
> requests are still welcome. If you are interested in maintaining the project,
> come and talk to us in `#test-kitchen` on
> [Chef Community Slack](https://community-slack.chef.io/).

## Reporting issues

Report bugs and request features on the [issue tracker](https://github.com/test-kitchen/kitchen-dsc/issues), keeping the note above in mind. For bugs, please include:

- the version of kitchen-dsc and Test Kitchen you are using
- the WMF version on the test instance
- your `kitchen.yml` and the DSC configuration script
- the output of the failing command, ideally with `-l debug`

## Development setup

Clone the repository and install the dependencies:

```sh
git clone https://github.com/test-kitchen/kitchen-dsc.git
cd kitchen-dsc
bundle install
```

## Tests and linting

Be aware of the current state of the tooling before you start:

- **There are no unit tests.** `spec/` contains only `spec_helper.rb`, with no
  spec files, so changes have to be verified manually against a real Windows
  instance.
- **The Rakefile's rspec task points at the wrong path.** It is configured with
  `--default-path test` and `-I test/spec`, but there is no `test/` directory.
  The Rakefile also defines no `default` task, so a bare `bundle exec rake` does
  nothing.
- **The Gemfile pins dead tooling.** It requires `chefstyle` and `cane`, both of
  which are superseded by [Cookstyle](https://github.com/chef/cookstyle) and do
  not work on modern Ruby.

For linting, run Cookstyle directly:

```sh
bundle exec cookstyle
bundle exec cookstyle -a   # autocorrect what can be corrected
```

Adding unit tests and replacing the dead linters with Cookstyle would be very
welcome contributions.

## Manual testing

Until there are unit tests, any change needs to be exercised against a real
Windows instance running WMF 4 or newer. You will need a driver that can supply
one, such as kitchen-vagrant, kitchen-hyperv, or kitchen-ec2.

Both project layouts are worth exercising, since they take different paths
through the provisioner:

- **module style**, using `configuration_script_folder` and `configuration_script`
- **repository style**, using `modules_path` to upload DSC resources

If your change touches gallery installation, test it on a WMF 5 instance, which
is required for `modules_from_gallery`.

## Submitting changes

1. Fork the repository.
2. Create a feature branch off `main`.
3. Make your change.
4. Describe how you verified it, since there are no automated tests to rely on.
5. Push the branch to your fork and open a pull request.

Please keep pull requests focused on a single change — it makes review much
faster. Update the documentation in `README.md` when you add or change a
configuration option.

## Release process

Releases are handled by the maintainers.

1. Update `lib/kitchen-dsc/version.rb` with the new version.
2. Update `CHANGELOG.md`.
3. Merge to `main`; the [publish workflow](.github/workflows/publish.yaml) builds
   the gem and pushes it to RubyGems.

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

Run everything the way CI does:

```sh
bundle exec rake          # linter + unit tests
bundle exec rake test     # unit tests only (this is what CI runs)
bundle exec rake style    # Cookstyle only
bundle exec cookstyle -a  # autocorrect what can be corrected
```

The unit tests live in `spec/` and use RSpec. They build a real
`Kitchen::Instance` around the provisioner — with the stock dummy driver,
transport and verifier — rather than mocking it, so `default_config` blocks and
`finalize_config!` run exactly as they do in a real converge. See
`spec/support/kitchen_helpers.rb`.

Two conventions are worth knowing before you add specs:

- **Drive the public API.** Most of `Kitchen::Provisioner::Dsc` is private, but
  every private method is reachable through `install_command`, `init_command`,
  `create_sandbox`, `prepare_command`, `run_command` or `finalize_config!`.
  Assert on the PowerShell those produce instead of calling private methods
  with `send`.
- **Match on fragments, not whole commands.** Test Kitchen wraps every command
  with environment setup that differs between a laptop and CI (`$env:CI` is
  only injected when `ENV["CI"]` is set), so `include` and `match` are stable
  where `eq` is not.

Useful environment variables:

| Variable | Effect |
| --- | --- |
| `SEED=12345` | reproduce a specific random ordering |
| `VERBOSE=1` | print full backtraces on failure |
| `ONLY_FAILURES=1` | rerun only what failed last time |
| `COVERAGE=false` | skip SimpleCov |
| `RSPEC_WARNINGS=true` | enable Ruby warnings |

Coverage is reported to `coverage/` after each run as a diagnostic. **It is not
a gate** — no build fails because a percentage moved, and neither the coverage
report nor the documentation build runs in CI.

## Documentation

The public API is documented with [YARD](https://yardoc.org/):

```sh
bundle exec rake yard         # build HTML docs into doc/
bundle exec rake yard:stats   # list any undocumented objects
bundle exec rake yard:server  # browse at http://localhost:8808
```

New methods should carry a YARD comment with `@param` and `@return` tags;
private helpers should also be tagged `@api private`. This is a convention, not
a CI check.

## Manual testing

The unit tests cover the PowerShell this gem generates and the files it stages,
but they cannot tell you whether DSC accepts that PowerShell. Any change to the
generated scripts should also be exercised against a real Windows instance
running WMF 4 or newer. You will need a driver that can supply
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
4. Add or update specs, and run `bundle exec rake`.
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

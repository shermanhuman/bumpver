defmodule IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  defp run(cmd, args, opts) do
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd, ".")

    System.cmd(cmd, args, cd: cd, env: env, stderr_to_stdout: true)
  end

  defp create_temp_project! do
    base = Path.join(System.tmp_dir!(), "bumpver_it_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(base)

    # scaffold a new Mix project
    {_out, 0} = run("mix", ["new", "it_app"], cd: base)
    project = Path.join(base, "it_app")

    mix_exs = Path.join(project, "mix.exs")
    content = File.read!(mix_exs)

    dep_entry = "      {:bumpver, path: #{inspect(File.cwd!())}, runtime: false},\n"

    new_content =
      Regex.replace(~r/defp\s+deps\s+do\s*\[([\s\S]*?)\]\s*end/m, content, fn _full, body ->
        "defp deps do\n    [\n#{dep_entry}#{body}    ]\n  end"
      end)

    File.write!(mix_exs, new_content)

    # initialize git and commit
    {_, 0} = run("git", ["init"], cd: project)
    {_, 0} = run("git", ["config", "user.email", "you@example.com"], cd: project)
    {_, 0} = run("git", ["config", "user.name", "Tester"], cd: project)
    {_, 0} = run("git", ["add", "."], cd: project)
    {_, 0} = run("git", ["commit", "-m", "initial"], cd: project)

    # fetch and compile dependency
    {out, code} = run("mix", ["deps.get"], cd: project, env: [])

    if code != 0 do
      flunk("deps.get failed: #{out}")
    end

    {out, code} = run("mix", ["compile"], cd: project, env: [])

    if code != 0 do
      flunk("compile failed: #{out}")
    end

    on_exit(fn -> File.rm_rf!(base) end)

    project
  end

  test "auto-bump and check flow" do
    project = create_temp_project!()

    {_out1, code1} = run("mix", ["bumpver.check"], cd: project, env: [])
    assert code1 != 0

    {out2, code2} = run("mix", ["bumpver.check", "--auto-bump", "--yes"], cd: project, env: [])
    assert code2 == 0
    assert String.contains?(out2, "Version auto-bumped")

    mix_exs = File.read!(Path.join(project, "mix.exs"))
    assert mix_exs =~ "version: \"0.1.1\""
  end

  test "mix alias install/uninstall and run" do
    project = create_temp_project!()

    {_out, code} = run("mix", ["bumpver.mix.install"], cd: project, env: [])
    assert code == 0

    mix_exs = File.read!(Path.join(project, "mix.exs"))
    assert mix_exs =~ "precommit"

    # Make the alias non-interactive for testing (CI-like)
    mix_exs_path = Path.join(project, "mix.exs")
    mix_content = File.read!(mix_exs_path)

    File.write!(
      mix_exs_path,
      String.replace(mix_content, "bumpver.check --auto-bump", "bumpver.check --auto-bump --yes")
    )

    # Running mix precommit should succeed
    {out2, code2} = run("mix", ["precommit"], cd: project, env: [{"MIX_ENV", "test"}])
    mix_exs_content = File.read!(Path.join(project, "mix.exs"))
    assert code2 == 0, "precommit failed: #{out2}\n--- mix.exs:\n#{mix_exs_content}"

    {out3, code3} = run("mix", ["bumpver.mix.uninstall", "--force"], cd: project, env: [])
    assert code3 == 0, "uninstall failed: #{out3}"
  end

  test "git hook install/uninstall" do
    project = create_temp_project!()

    {_out1, code1} =
      run("mix", ["bumpver.git.install", "--auto-bump", "--yes"], cd: project, env: [])

    assert code1 == 0

    hook = Path.join([project, ".git", "hooks", "pre-commit"])
    assert File.exists?(hook)
    assert File.read!(hook) =~ "mix bumpver.check"

    {_out2, code2} = run("mix", ["bumpver.git.uninstall"], cd: project, env: [])
    assert code2 == 0
    refute File.exists?(hook)
  end

  test "interactive-required fails when no tty (CI)" do
    project = create_temp_project!()

    {out, code} =
      run("mix", ["bumpver.check", "--auto-bump"],
        cd: project,
        env: [{"MIX_ENV", "test"}, {"CI", "1"}]
      )

    assert code != 0
    assert String.contains?(out, "Cannot run interactive bump (no TTY detected)")
  end
end

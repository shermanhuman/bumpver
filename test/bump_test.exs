defmodule BumpverTest do
  use ExUnit.Case

  describe "extract_version/1" do
    test "extracts @version" do
      content = """
      defmodule X.MixProject do
        use Mix.Project
        @version \"1.2.3\"
        def project, do: [app: :x, version: @version]
      end
      """

      assert Bumpver.extract_version(content) == "1.2.3"
    end

    test "extracts version: \"...\"" do
      content = """
      defmodule X.MixProject do
        use Mix.Project
        def project, do: [app: :x, version: \"0.9.0\"]
      end
      """

      assert Bumpver.extract_version(content) == "0.9.0"
    end
  end

  describe "ensure_consistent_versions!/1" do
    test "passes when only one pattern exists" do
      content = """
      defmodule X.MixProject do
        use Mix.Project
        def project, do: [app: :x, version: \"1.2.3\"]
      end
      """

      assert :ok == Bumpver.ensure_consistent_versions!(content)
    end

    test "passes when both patterns exist and match" do
      content = """
      defmodule X.MixProject do
        use Mix.Project
        @version \"1.2.3\"
        def project, do: [app: :x, version: \"1.2.3\"]
      end
      """

      assert :ok == Bumpver.ensure_consistent_versions!(content)
    end

    test "raises when both patterns exist and differ" do
      content = """
      defmodule X.MixProject do
        use Mix.Project
        @version \"1.2.3\"
        def project, do: [app: :x, version: \"1.2.4\"]
      end
      """

      assert_raise ArgumentError, ~r/Conflicting versions found/, fn ->
        Bumpver.ensure_consistent_versions!(content)
      end
    end
  end

  describe "update_mix_exs_content/2" do
    test "updates both @version and version: when they match" do
      content = """
      defmodule X.MixProject do
        use Mix.Project
        @version \"1.2.3\"
        def project, do: [app: :x, version: \"1.2.3\"]
      end
      """

      updated = Bumpver.update_mix_exs_content(content, "1.2.4")
      assert updated =~ "@version \"1.2.4\""
      assert updated =~ "version: \"1.2.4\""
    end
  end

  describe "bump_version/2" do
    test "bumps major" do
      assert Bumpver.bump_version("1.2.3", :major) == "2.0.0"
    end

    test "bumps minor" do
      assert Bumpver.bump_version("1.2.3", :minor) == "1.3.0"
    end

    test "bumps patch" do
      assert Bumpver.bump_version("1.2.3", :patch) == "1.2.4"
    end
  end
end

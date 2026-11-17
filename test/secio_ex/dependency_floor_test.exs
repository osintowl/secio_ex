defmodule SecioEx.DependencyFloorTest do
  use ExUnit.Case, async: true

  test "shared http requirements exclude vulnerable releases and keep patched lines" do
    req = requirement(:req)
    assert_rejects(req, ["0.5.18", "0.6.0", "0.8.0"])
    assert_accepts(req, ["0.6.1", "0.6.3", "0.7.0", "0.7.5"])

    mint = requirement(:mint)
    assert_rejects(mint, ["1.6.2", "1.9.3", "1.10.1", "2.0.0"])
    assert_accepts(mint, ["1.10.2", "1.11.0"])

    hpax = requirement(:hpax)
    assert_rejects(hpax, ["0.1.1", "0.2.0", "1.0.3", "2.0.0"])
    assert_accepts(hpax, ["1.0.4", "1.1.0"])

    finch = requirement(:finch)
    assert_rejects(finch, ["0.20.0", "1.0.0"])
    assert_accepts(finch, ["0.21.0", "0.24.0"])
  end

  test "test dependencies exclude vulnerable plug releases" do
    plug = requirement(:plug)
    assert_rejects(plug, ["1.15.3", "1.19.5", "1.20.3", "2.0.0"])
    assert_accepts(plug, ["1.20.4"])

    plug_crypto = requirement(:plug_crypto)
    assert_rejects(plug_crypto, ["1.2.5", "2.0.0", "2.2.0", "3.0.0"])
    assert_accepts(plug_crypto, ["2.2.1"])
  end

  defp requirement(name) do
    found =
      Enum.find_value(Mix.Project.config()[:deps], fn
        {^name, requirement, _opts} -> requirement
        {^name, requirement} -> requirement
        _ -> nil
      end)

    assert found, "#{name} has no version requirement"
    found
  end

  defp assert_accepts(requirement, versions) do
    for version <- versions do
      assert Version.match?(version, requirement),
             "#{version} should match #{inspect(requirement)}"
    end
  end

  defp assert_rejects(requirement, versions) do
    for version <- versions do
      refute Version.match?(version, requirement),
             "#{version} should not match #{inspect(requirement)}"
    end
  end
end

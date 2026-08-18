defmodule Tuix.Runtime.ClickTest do
  use ExUnit.Case, async: true

  alias Tuix.Event.Mouse
  alias Tuix.Runtime.Click

  defp mouse(kind, opts \\ []) do
    struct!(Mouse, [kind: kind] ++ opts)
  end

  test "press then release on the same target synthesizes a click" do
    {pressed, nil} = Click.track(nil, mouse(:press, button: :left, target: :ok_button))

    assert {nil, click} =
             Click.track(
               pressed,
               mouse(:release, button: :left, target: :ok_button, x: 3, y: 2)
             )

    assert %Mouse{kind: :click, button: :left, target: :ok_button, x: 3, y: 2} = click
  end

  test "releasing over a different target cancels the click" do
    {pressed, nil} = Click.track(nil, mouse(:press, button: :left, target: :ok_button))

    assert {nil, nil} =
             Click.track(pressed, mouse(:release, button: :left, target: :cancel_button))
  end

  test "dragging within the target does not cancel the click" do
    {pressed, nil} = Click.track(nil, mouse(:press, button: :left, target: :ok_button))
    {pressed, nil} = Click.track(pressed, mouse(:drag, button: :left, target: :ok_button))
    {pressed, nil} = Click.track(pressed, mouse(:drag, button: :left, target: nil))

    assert {nil, %Mouse{kind: :click, target: :ok_button}} =
             Click.track(pressed, mouse(:release, button: :left, target: :ok_button))
  end

  test "clicks on empty space fire with a nil target" do
    {pressed, nil} = Click.track(nil, mouse(:press, button: :left, target: nil))

    assert {nil, %Mouse{kind: :click, button: :left, target: nil}} =
             Click.track(pressed, mouse(:release, button: :left, target: nil))
  end

  test "right and middle buttons click too" do
    for button <- [:right, :middle] do
      {pressed, nil} = Click.track(nil, mouse(:press, button: button, target: :menu))

      assert {nil, %Mouse{kind: :click, button: ^button}} =
               Click.track(pressed, mouse(:release, button: button, target: :menu))
    end
  end

  test "an X10 release (nil button) completes the click with the pressed button" do
    {pressed, nil} = Click.track(nil, mouse(:press, button: :left, target: :ok_button))

    assert {nil, %Mouse{kind: :click, button: :left, target: :ok_button}} =
             Click.track(pressed, mouse(:release, button: nil, target: :ok_button))
  end

  test "a release of a different button neither clicks nor clears" do
    {pressed, nil} = Click.track(nil, mouse(:press, button: :left, target: :ok_button))

    assert {^pressed, nil} =
             Click.track(pressed, mouse(:release, button: :right, target: :ok_button))
  end

  test "a release without a tracked press does nothing" do
    assert {nil, nil} = Click.track(nil, mouse(:release, button: :left, target: :ok_button))
  end

  test "scroll and press-tracking are independent" do
    {pressed, nil} = Click.track(nil, mouse(:press, button: :left, target: :ok_button))
    assert {^pressed, nil} = Click.track(pressed, mouse(:scroll_up, target: :ok_button))
  end

  test "a new press replaces the tracked one" do
    {pressed, nil} = Click.track(nil, mouse(:press, button: :left, target: :a))
    {pressed, nil} = Click.track(pressed, mouse(:press, button: :left, target: :b))

    assert {nil, %Mouse{kind: :click, target: :b}} =
             Click.track(pressed, mouse(:release, button: :left, target: :b))
  end
end

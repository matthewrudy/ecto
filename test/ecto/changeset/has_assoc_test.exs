defmodule Ecto.Changeset.HasAssocTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation

  alias __MODULE__.Author
  alias __MODULE__.Post
  alias __MODULE__.Summary
  alias __MODULE__.Profile

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
      belongs_to :author, Author
      belongs_to :summary, Summary
    end

    def changeset(model, params) do
      Changeset.cast(model, params, ~w(title), ~w(author_id))
    end

    def set_action(model, params) do
      Changeset.cast(model, params, ~w(title), [])
      |> Map.put(:action, :update)
    end
  end

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :title, :string
      has_many :posts, Post, on_replace: :delete
      has_one :profile, {"users_profiles", Profile},
        defaults: [name: "default"], on_replace: :delete
    end
  end

  defmodule Summary do
    use Ecto.Schema

    schema "summaries" do
      has_one :post, Post, defaults: [title: "default"], on_replace: :nilify
      has_many :posts, Post, on_replace: :nilify
    end
  end

  defmodule Profile do
    use Ecto.Schema

    schema "profiles" do
      field :name
      belongs_to :author, Author
      belongs_to :summary, Summary
    end

    def changeset(model, params) do
      Changeset.cast(model, params, ~w(name), ~w(id))
    end

    def optional_changeset(model, params) do
      Changeset.cast(model, params, ~w(), ~w(name))
    end

    def set_action(model, params) do
      Changeset.cast(model, params, ~w(name), ~w(id))
      |> Map.put(:action, :update)
    end
  end

  defp cast(model, params, assoc, opts \\ []) do
    model
    |> Changeset.cast(params, ~w(), ~w())
    |> Changeset.cast_assoc(assoc, opts)
  end

  ## cast has_one

  test "cast has_one with valid params" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one with invalid params" do
    changeset = cast(%Author{}, %{"profile" => %{name: nil}}, :profile)
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == [name: "can't be blank"]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = cast(%Author{}, %{"profile" => "value"}, :profile)
    assert changeset.errors == [profile: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_one with existing model updating" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new", "id" => 1}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one without loading" do
    assert cast(%Author{}, %{"profile" => nil}, :profile).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise RuntimeError, ~r"attempting to cast or change association `profile` .* that was not loaded", fn ->
      cast(loaded, %{"profile" => nil}, :profile)
    end
  end

  test "cast has_one with existing model replacing" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new"}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = cast(%Author{profile: %Profile{name: "michal", id: 2}},
                     %{"profile" => %{"name" => "new", "id" => 5}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new", id: 5}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
           %{"profile" => %{"name" => "new", "id" => "new"}},
           :profile, with: &Profile.set_action/2)
    end
  end

  test "cast has_one without changes skips" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"id" => 1}}, :profile)
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"id" => "1"}}, :profile)
    assert changeset.changes == %{}
    assert changeset.errors == []
  end

  test "cast has_one when required" do
    changeset = cast(%Author{}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset = cast(%Author{profile: nil}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset = cast(%Author{profile: %Profile{}}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{profile: nil}, %{"profile" => nil}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset = cast(%Author{profile: %Profile{}}, %{"profile" => nil}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{profile: nil}
    assert changeset.errors == [profile: "can't be blank"]
  end

  test "cast has_one with optional" do
    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{"profile" => nil}, :profile)
    assert changeset.changes.profile == nil
  end

  test "cast has_one with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{}}, :profile, with: &Profile.optional_changeset/2)
    profile = changeset.changes.profile
    assert profile.model.name == "default"
    assert profile.model.__meta__.source == {nil, "users_profiles"}
    assert profile.changes == %{}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one keeps appropriate action from changeset" do
    changeset = cast(%Author{profile: %Profile{id: "id"}},
                     %{"profile" => %{"name" => "michal", "id" => "id"}},
                     :profile, with: &Profile.set_action/2)
    assert changeset.changes.profile.action == :update

    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      cast(%Author{profile: %Profile{id: "old"}},
           %{"profile" => %{"name" => "michal", "id" => "new"}},
           :profile, with: &Profile.set_action/2)
    end
  end

  test "cast has_one with :empty parameters" do
    changeset = cast(%Author{profile: nil}, :empty, :profile)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, :empty, :profile, required: true)
    assert changeset.changes == %{}

    changeset = cast(%Author{profile: %Profile{}}, :empty, :profile, required: true)
    assert changeset.changes == %{}
  end

  test "cast has_one with on_replace: :raise" do
    model = %Summary{post: %Post{id: 1}}

    params = %{"post" => %{"name" => "jose", "id" => "1"}}
    changeset = cast(model, params, :post, on_replace: :raise)
    assert changeset.changes.post.action == :update

    params = %{"post" => nil}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, params, :post, on_replace: :raise)
    end

    params = %{"post" => %{"name" => "new", "id" => 2}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, params, :post, on_replace: :raise)
    end
  end

  test "cast has_one with on_replace: :mark_as_invalid" do
    model = %Summary{post: %Post{id: 1}}

    changeset = cast(model, %{"post" => nil}, :post, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [post: "is invalid"]
    refute changeset.valid?

    changeset = cast(model, %{"post" => %{"id" => 2}}, :post, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [post: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_one twice" do
    model = %Author{}
    params = %{profile: %{name: "Bruce Wayne", id: 1}}
    model = cast(model, params, :profile) |> Changeset.apply_changes
    params = %{profile: %{name: "Batman", id: 1}}
    changeset = cast(model, params, :profile)
    changeset = cast(changeset, params, :profile)
    assert changeset.valid?

    model = %Author{}
    params = %{profile: %{name: "Bruce Wayne"}}
    changeset = cast(model, params, :profile)
    changeset = cast(changeset, params, :profile)
    assert changeset.valid?
  end

  ## cast has_many

  test "cast has_many with only new models" do
    changeset = cast(%Author{}, %{"posts" => [%{"title" => "hello"}]}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast has_many with map" do
    changeset = cast(%Author{}, %{"posts" => %{0 => %{"title" => "hello"}}}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast has_many without loading" do
    assert cast(%Author{}, %{"posts" => []}, :posts).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise RuntimeError, ~r"attempting to cast or change association `posts` .* that was not loaded", fn ->
      cast(loaded, %{"posts" => []}, :posts)
    end
  end

  # Please note the order is important in this test.
  test "cast has_many changing models" do
    posts = [%Post{title: "first", id: 1},
             %Post{title: "second", id: 2},
             %Post{title: "third", id: 3}]
    params = [%{"title" => "new"},
              %{"id" => 2, "title" => nil},
              %{"id" => 3, "title" => "new name"}]

    changeset = cast(%Author{posts: posts}, %{"posts" => params}, :posts)
    [first, new, second, third] = changeset.changes.posts

    assert first.model.id == 1
    assert first.required == [] # Check for not running changeset function
    assert first.action == :delete
    assert first.valid?

    assert new.changes == %{title: "new"}
    assert new.action == :insert
    assert new.valid?

    assert second.model.id == 2
    assert second.errors == [title: "can't be blank"]
    assert second.action == :update
    refute second.valid?

    assert third.model.id == 3
    assert third.action == :update
    assert third.valid?

    refute changeset.valid?
  end

  test "cast has_many with invalid operation" do
    params = %{"posts" => [%{"id" => 1, "title" => "new"}]}
    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      cast(%Author{posts: []}, params, :posts, with: &Post.set_action/2)
    end
  end

  test "cast has_many with invalid params" do
    changeset = cast(%Author{}, %{"posts" => "value"}, :posts)
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => ["value"]}, :posts)
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => nil}, :posts)
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => %{"id" => "invalid"}}, :posts)
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_many without changes skips" do
    changeset = cast(%Author{posts: [%Post{title: "hello", id: 1}]},
                     %{"posts" => [%{"id" => 1}]}, :posts)

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "cast has_many when required" do
    # Still no error because the loaded association is an empty list
    changeset = cast(%Author{}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{posts: []}, %{"posts" => nil}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
  end

  test "cast has_many with :empty parameters" do
    changeset = cast(%Author{posts: []}, :empty, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, :empty, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{posts: [%Post{}]}, :empty, :posts)
    assert changeset.changes == %{}
  end

  test "cast has_many with on_replace: :raise" do
    model = %Summary{posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, %{"posts" => []}, :posts, on_replace: :raise)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, %{"posts" => [%{"id" => 2}]}, :posts, on_replace: :raise)
    end
  end

  test "cast has_many with on_replace: :mark_as_invalid" do
    model = %Summary{posts: [%Post{id: 1}]}

    changeset = cast(model, %{"posts" => []}, :posts, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(model, %{"posts" => [%{"id" => 2}]}, :posts, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_many twice" do
    model = %Author{}

    params = %{posts: [%{title: "hello", id: 1}]}
    model = cast(model, params, :posts) |> Changeset.apply_changes
    params = %{posts: []}
    changeset = cast(model, params, :posts)
    changeset = cast(changeset, params, :posts)
    assert changeset.valid?

    model = %Author{}
    params = %{posts: [%{title: "hello"}]}
    changeset = cast(model, params, :posts)
    changeset = cast(changeset, params, :posts)
    assert changeset.valid?
  end

  ## Change

  test "change has_one" do
    assoc = Author.__schema__(:association, :profile)

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, %Profile{name: "michal"}, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal", summary_id: nil, author_id: nil}

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, nil, %Profile{})
    assert changeset.action == :delete

    assoc_model = %Profile{}
    assoc_model_changeset = Changeset.change(assoc_model, name: "michal")

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, assoc_model_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal", summary_id: nil, author_id: nil}

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, assoc_model_changeset, assoc_model)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    empty_changeset = Changeset.change(assoc_model)
    assert {:ok, _, true, true} =
      Relation.change(assoc, empty_changeset, assoc_model)

    assoc_with_id = %Profile{id: 2}
    assert {:ok, _, true, false} =
      Relation.change(assoc, %Profile{id: 1}, assoc_with_id)

    update_changeset = %{Changeset.change(assoc_model) | action: :delete}
    assert_raise RuntimeError, ~r"cannot delete .* it does not exist in the parent model", fn ->
      Relation.change(assoc, update_changeset, assoc_with_id)
    end
  end

  test "change has_one keeps appropriate action from changeset" do
    assoc = Author.__schema__(:association, :profile)
    assoc_model = %Profile{}

    changeset = %{Changeset.change(assoc_model, name: "michal") | action: :insert}

    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :insert

    changeset = %{changeset | action: :delete}
    assert_raise RuntimeError, ~r"cannot delete .* it does not exist in the parent model", fn ->
      Relation.change(assoc, changeset, nil)
    end

    changeset = %{Changeset.change(assoc_model) | action: :update}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, assoc_model)
    assert changeset.action == :update

    assoc_model = %{assoc_model | id: 5}
    changeset = %{Changeset.change(assoc_model) | action: :insert}
    assert_raise RuntimeError, ~r"cannot insert .* it already exists in the parent model", fn ->
      Relation.change(assoc, changeset, assoc_model)
    end
  end

  test "change has_one with on_replace: :raise" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Summary{post: assoc_model})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :post, nil, on_replace: :raise)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :post, %Post{id: 2}, on_replace: :raise)
    end
  end

  test "change has_one with on_replace: :mark_as_invalid" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Summary{post: assoc_model})

    changeset = Changeset.put_assoc(base_changeset, :post, nil, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [post: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :post, %Post{id: 2}, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [post: "is invalid"]
    refute changeset.valid?
  end

  test "change has_many" do
    assoc = Author.__schema__(:association, :posts)

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [%Post{title: "hello"}], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, title: "hello", summary_id: nil, author_id: nil}

    assert {:ok, [old_changeset, new_changeset], true, false} =
      Relation.change(assoc, [%Post{id: 1}], [%Post{id: 2}])
    assert old_changeset.action  == :delete
    assert new_changeset.action  == :insert
    assert new_changeset.changes == %{id: 1, title: nil, summary_id: nil, author_id: nil}

    assoc_model_changeset = Changeset.change(%Post{}, title: "hello")

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [assoc_model_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, title: "hello", summary_id: nil, author_id: nil}

    assoc_model = %Post{id: 1}
    assoc_model_changeset = Changeset.change(assoc_model, title: "hello")
    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [assoc_model_changeset], [assoc_model])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [], [assoc_model_changeset])
    assert changeset.action == :delete

    empty_changeset = Changeset.change(assoc_model)
    assert {:ok, _, true, true} =
      Relation.change(assoc, [empty_changeset], [assoc_model])

    new_model_update = %{Changeset.change(%Post{id: 2}) | action: :update}
    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      Relation.change(assoc, [new_model_update], [assoc_model])
    end

    assert_raise RuntimeError, ~r"use a changeset instead", fn ->
      Relation.change(assoc, [%Post{id: 1, title: "hello"}], [%Post{id: 1}])
    end
  end

  test "change has_many with on_replace: :raise" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Summary{posts: [assoc_model]})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :posts, [], on_replace: :raise)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :posts, [%Post{id: 2}], on_replace: :raise)
    end
  end

  test "change has_many with on_replace: :mark_as_invalid" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Summary{posts: [assoc_model]})

    changeset = Changeset.put_assoc(base_changeset, :posts, [], on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :posts, [%Post{id: 2}], on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :posts, [], on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :posts, [%Post{id: 2}], on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?
  end

  ## Other

  test "put_assoc/4" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.put_assoc(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_assoc(base_changeset, :profile, empty_update_changeset)
    refute Map.has_key?(changeset.changes, :profile)
  end

  test "get_field/3, fetch_field/2 with assocs" do
    profile_changeset = Changeset.change(%Profile{}, name: "michal")
    profile = Changeset.apply_changes(profile_changeset)

    changeset =
      %Author{}
      |> Changeset.change
      |> Changeset.put_assoc(:profile, profile_changeset)
    assert Changeset.get_field(changeset, :profile) == profile
    assert Changeset.fetch_field(changeset, :profile) == {:changes, profile}

    changeset = Changeset.change(%Author{profile: profile})
    assert Changeset.get_field(changeset, :profile) == profile
    assert Changeset.fetch_field(changeset, :profile) == {:model, profile}

    post = %Post{id: 1}
    post_changeset = %{Changeset.change(post) | action: :delete}
    changeset =
      %Author{posts: [post]}
      |> Changeset.change
      |> Changeset.put_assoc(:posts, [post_changeset])
    assert Changeset.get_field(changeset, :posts) == []
    assert Changeset.fetch_field(changeset, :posts) == {:changes, []}
  end

  test "on_replace: :nilify" do
    # one case is handled inside repo
    post = %Post{id: 1, summary_id: 5}
    changeset = cast(%Summary{post: post}, %{"post" => nil}, :post)
    assert changeset.changes.post == nil

    changeset = cast(%Summary{posts: [post]}, %{"posts" => []}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.action == :update
    assert post_change.changes == %{summary_id: nil}
  end

  test "apply_changes" do
    embed = Author.__schema__(:association, :profile)

    changeset = Changeset.change(%Profile{}, name: "michal")
    model = Relation.apply_changes(embed, changeset)
    assert model == %Profile{name: "michal"}

    changeset = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset | action: :delete}
    assert Relation.apply_changes(embed, changeset2) == nil

    embed = Author.__schema__(:association, :posts)
    [model] = Relation.apply_changes(embed, [changeset, changeset2])
    assert model == %Post{title: "hello"}
  end
end

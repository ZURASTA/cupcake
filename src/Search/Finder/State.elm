module Search.Finder.State exposing (init, update, subscriptions)

import Search.Finder.Types exposing (..)
import Search.Filter exposing (..)
import Http
import Json.Decode
import Time
import Regex


init : ( Model, Cmd Msg )
init =
    ( model, Cmd.none )


model : Model
model =
    Empty


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Query "" ->
            ( Empty, Cmd.none )

        Query query ->
            case model of
                Empty ->
                    ( Autocomplete query Nothing, getSuggestions query )

                Autocomplete _ suggestions ->
                    {- Possibly pass the old suggestions state to the request
                       to the server query. So it can either apply temporary
                       filtering to the previous results while waiting for
                       new results to come in. Or possibly just remove it
                       entirely, in which case this case statement could be
                       replaced with the same result.
                    -}
                    ( Autocomplete query Nothing, getSuggestions query )

        Select filter ->
            ( Empty, Cmd.none )

        NewSuggestions response ->
            case model of
                Autocomplete query _ ->
                    let
                        suggestions =
                            case response of
                                Ok suggestions ->
                                    suggestions

                                Err _ ->
                                    FilterSuggestions [] [] [] [] []

                        filters =
                            List.concat
                                [ [ (Filter Name ( query, Nothing )) ]
                                , List.map (\name -> Filter Ingredient name) suggestions.ingredients
                                , List.map (\name -> Filter Cuisine name) suggestions.cuisines
                                , List.map (\name -> Filter Allergen name) suggestions.allergens
                                , List.map (\name -> Filter Diet name) suggestions.diets
                                , List.map (\name -> Filter RegionalStyle name) suggestions.regionalStyles
                                , List.map (\name -> Filter Price name) (getPrices query)
                                ]
                    in
                        ( Autocomplete query (Just filters), Cmd.none )

                _ ->
                    ( model, Cmd.none )


currencySymbols : List String
currencySymbols =
    [ "$"
    ]


getPrices : String -> List ( String, Maybe ID )
getPrices query =
    --TODO: Fix regex to be less greedy
    let
        prices =
            Regex.find (Regex.AtMost 2) (Regex.regex ("(?![" ++ (List.foldr (++) "" currencySymbols) ++ "])\\d+\\.?\\d*")) query

        ranges =
            case prices of
                [ a, b ] ->
                    [ ( a.match ++ " - " ++ b.match, Nothing ) ]

                [ { match } ] ->
                    let
                        base =
                            case String.toFloat match of
                                Ok value ->
                                    truncate value

                                Err _ ->
                                    0
                    in
                        --TODO: Don't do subtractions if base will be below 0
                        [ ( match, Nothing )
                        , ( "0 - " ++ match, Nothing )
                        , ( (toString (base - 20)) ++ " - " ++ match, Nothing )
                        , ( (toString (base - 10)) ++ " - " ++ match, Nothing )
                        , ( match ++ " - " ++ (toString (base + 10)), Nothing )
                        , ( match ++ " - " ++ (toString (base + 20)), Nothing )
                        ]

                _ ->
                    []
    in
        ranges


getSuggestions : String -> Cmd Msg
getSuggestions query =
    -- TODO: Convert to using elm-graphql once the library support 0.18
    let
        request =
            Http.request
                { method = "POST"
                , headers =
                    [ (Http.header "Accept" "application/json")
                    ]
                , url = "http://localhost:4000?variables={\"term\":\"" ++ query ++ "\"}"
                , body =
                    Http.stringBody "application/graphql"
                        """
                        query suggestions($term: String!) {
                            ingredients(name: $term) { id name }
                            cuisines(name: $term) { id name }
                            allergens(name: $term) { id name }
                            diets(name: $term) { id name }
                            regions(find: $term) { id style }
                        }
                        """
                , expect = Http.expectJson decodeSuggestions
                , timeout = Nothing
                , withCredentials = False
                }
    in
        Http.send NewSuggestions request


decodeFilterField : String -> Json.Decode.Decoder ( String, Maybe ID )
decodeFilterField name =
    (Json.Decode.map2 (\id string -> ( string, Just id )) (Json.Decode.field "id" Json.Decode.string) (Json.Decode.field name Json.Decode.string))


decodeSuggestions : Json.Decode.Decoder FilterSuggestions
decodeSuggestions =
    let
        fields =
            Json.Decode.map5
                (\ingredients cuisines allergens diets regionalStyles ->
                    { ingredients = ingredients
                    , cuisines = cuisines
                    , allergens = allergens
                    , diets = diets
                    , regionalStyles = regionalStyles
                    }
                )
                (Json.Decode.field "ingredients" (Json.Decode.list (decodeFilterField "name")))
                (Json.Decode.field "cuisines" (Json.Decode.list (decodeFilterField "name")))
                (Json.Decode.field "allergens" (Json.Decode.list (decodeFilterField "name")))
                (Json.Decode.field "diets" (Json.Decode.list (decodeFilterField "name")))
                (Json.Decode.field "regions" (Json.Decode.list (decodeFilterField "style")))
    in
        Json.Decode.field "data" fields


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none

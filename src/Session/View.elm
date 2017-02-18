module Session.View exposing (..)

import Html exposing (..)
import Session.Types exposing (..)
import Session.Active.View as Active
import Session.Inactive.View as Inactive


render : Model -> Html Msg
render model =
    div []
        [ map (\msg -> Active msg) (Active.render model.active)
        , map (\msg -> Inactive msg) (Inactive.render model.inactive)
        ]
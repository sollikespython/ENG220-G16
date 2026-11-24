import streamlit as st
import pandas as pd
import numpy as np

st.title ('How much could a Cuba resident save on power using solar?')

st.markdown("What will you be powering?")

house = st.checkbox("A household.")
indus = st.checkbox("An industrial plant or factory.")
comm = st.checkbox("A commercial storefront.")

spanel = st.number_input("How many 2x1 meter solar panels can you fit on your property in direct sunlight?")

savedF = 1
savedP = 1
totSaved = 1
rCost = 0.1651
iCost = 0.0508
cCost = 0.1214

if house:
    savedF = 3600 * rCost * spanel
    savedP = 1560 * rCost * spanel
    totSaved = savedF + savedP
    totUsed = 899 * rCost
    if totUsed <= totSaved:
        st.markdown(f"You could cover your entire electricity bill if you install {spanel} solar panels!")
    else:
        st.markdown(f"You could save ${totSaved} on your electricity bill if you install {spanel} solar panels!")



if indus:
    savedF = 3600 * iCost * spanel
    savedP = 1560 * rCost * spanel
    totSaved = savedF + savedP
    totUsed = 833300 * iCost
    if totUsed <= totSaved:
            st.markdown(f"You could cover your entire electricity bill if you install {spanel} solar panels!")
    else:
        st.markdown(f"You could save ${totSaved} on your electricity bill if you install {spanel} solar panels!")
    

if comm:
    savedF = 3600 * cCost * spanel
    savedP = 1560 * cCost * spanel
    totSaved = savedF + savedP
    totUsed = 6000 * cCost
    if totUsed <= totSaved:
            st.markdown(f"You could cover your entire electricity bill if you install {spanel} solar panels!")
    else:
        st.markdown(f"You could save ${totSaved} on your electricity bill if you install {spanel} solar panels!")
    

st.markdown(f"Thanks for using the solar calculator!")

